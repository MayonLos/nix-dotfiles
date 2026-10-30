#!/usr/bin/env python3
"""Run PP-OCRv4 ONNX CPU and score both OCR-derived layout and oracle geometry."""
import argparse, hashlib, json, re, time, resource, importlib.metadata
from pathlib import Path

DAY_WORDS = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5}


def clean(s):
    # Ignore spacing around line breaks/labels only. Preserve digits, commas,
    # week punctuation and parentheses because they carry timetable meaning.
    return re.sub(r"[\s\u3000:：]+", "", s)


def norm_points(box):
    if isinstance(box, (list, tuple)) and len(box) == 4 and all(isinstance(v,(int,float)) for v in box):
        x0,y0,x1,y1=box
        return [[x0,y0],[x1,y0],[x1,y1],[x0,y1]]
    return [[float(p[0]),float(p[1])] for p in box]


def center(poly):
    return sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly)


def weekday(text):
    m=re.search(r"(?:星期|周)\s*([一二三四五])",text)
    return DAY_WORDS[m.group(1)] if m else None


def period_no(text):
    m=re.search(r"第\s*([1-6一二三四五六])\s*(?:节|堂)",text)
    if not m: return None
    val=m.group(1)
    return int(val) if val.isdigit() else "一二三四五六".index(val)+1


def fit_axis(anchors):
    """Least-squares map from image coordinate to ordinal index, with no truth geometry."""
    if len({a for a,_ in anchors}) < 2: return None
    xs=[float(x) for _,x in anchors]; ys=[float(y) for y,_ in anchors]
    mx=sum(xs)/len(xs); my=sum(ys)/len(ys)
    denom=sum((x-mx)**2 for x in xs)
    if denom == 0: return None
    slope=sum((x-mx)*(y-my) for x,y in zip(xs,ys))/denom
    if slope == 0: return None
    intercept=my-slope*mx
    return lambda coord: int(round(slope*coord+intercept))


def infer_layout(detections):
    day_anchors=[]; period_anchors=[]; anchor_ids=set()
    for i,item in enumerate(detections):
        x,y=center(item["box"]); d=weekday(item["text"]); p=period_no(item["text"])
        if d is not None: day_anchors.append((d,x)); anchor_ids.add(i)
        if p is not None: period_anchors.append((p,y)); anchor_ids.add(i)
    day_at=fit_axis(day_anchors); period_at=fit_axis(period_anchors)
    for i,item in enumerate(detections):
        x,y=center(item["box"]); day=day_at(x) if day_at else None; period=period_at(y) if period_at else None
        item["cell"]=(day,period) if i not in anchor_ids and day in range(1,6) and period in range(1,7) else None
    return len(day_anchors),len(period_anchors)


def oracle_cell(x,y,sample):
    """Diagnostic only: map through synthetic ground-truth geometry, never product prediction."""
    H=sample.get('homography')
    if H:
        import numpy as np
        inv=np.linalg.inv(np.array(H,dtype='float64'))
        p=inv @ np.array([x,y,1.0]); x,y=p[0]/p[2],p[1]/p[2]
    g=sample['grid']; c=int((x-g['left'])//g['cellWidth']); r=int((y-g['top'])//g['cellHeight'])
    return (c,r) if 1<=c<=g['days'] and 1<=r<=g['periods'] else None


def score(expected, detections, key):
    correct=recognition=layout=missed=empty_correct=empty_false=detected=0; cells=[]
    for day in range(1,6):
        for period in range(1,7):
            exp=expected.get((day,period),"")
            vals=[d["text"] for d in detections if d[key]==(day,period)]
            pred="".join(vals); exact=clean(pred)==clean(exp); failure=None
            if exp:
                if vals:
                    detected+=1
                    if exact: correct+=1
                    else: recognition+=1; failure="recognition"
                elif any(clean(d["text"])==clean(exp) and d[key]!=(day,period) for d in detections):
                    layout+=1; failure="layout"
                else:
                    missed+=1; failure="detection"
            elif exact: empty_correct+=1
            else: empty_false+=1
            cells.append({"day":day,"period":period,"expected":exp,"predicted":pred,"correct":exact,"failure":failure})
    return {"correct":correct,"recognitionWrong":recognition,"layoutWrong":layout,"detectionMissed":missed,"detected":detected,"emptyCorrect":empty_correct,"emptyFalsePositive":empty_false,"cells":cells}



def _self_check():
    axis=fit_axis([(1,100),(2,200)])
    assert axis is not None and axis(100)==1 and axis(200)==2
    assert clean("1-16周(单)")=="1-16周(单)"


def main():
    _self_check()
    ap=argparse.ArgumentParser(); ap.add_argument('--data',required=True); ap.add_argument('--out',required=True); a=ap.parse_args()
    from rapidocr_onnxruntime import RapidOCR
    data=Path(a.data); out=Path(a.out); out.mkdir(parents=True,exist_ok=True)
    truth=json.loads((data/'truth.json').read_text(encoding='utf-8'))['samples']; run_start=time.perf_counter(); engine=RapidOCR(intra_op_num_threads=2,inter_op_num_threads=1)
    records=[]; allboxes=[]; model_hashes={}; total_ms=0; day_anchor_count=period_anchor_count=0
    for sample in truth:
        t=time.perf_counter(); result,_=engine(str(data/sample['image'])); elapsed=(time.perf_counter()-t)*1000; total_ms+=elapsed
        detections=[]
        for box,text,confidence in result or []:
            poly=norm_points(box); x,y=center(poly)
            detections.append({"text":str(text),"confidence":float(confidence),"box":poly,"center":(x,y),"cell":None,"oracleCell":oracle_cell(x,y,sample)})
        da,pa=infer_layout(detections); day_anchor_count+=da; period_anchor_count+=pa
        expected={(x['day'],x['period']):x['text'] for x in sample['occupied']}
        raw=score(expected,detections,'cell'); oracle=score(expected,detections,'oracleCell')
        recognized=[clean(d['text']) for d in detections]
        used=set(); field_counts={}
        for field in sample.get('richFields',[]):
            typ=field['field']; field_counts.setdefault(typ,[0,0]); field_counts[typ][1]+=1
            target=clean(field['expected'])
            match=next((j for j,text in enumerate(recognized) if j not in used and text==target),None)
            if match is not None: field_counts[typ][0]+=1; used.add(match)
        merge_texts=[clean(x['text']) for x in sample.get('mergeCells',[])]
        merge_correct=sum(any(clean(d['text'])==expected_text for d in detections) for expected_text in merge_texts)
        for d in detections:
            c=d['cell']; poly=d['box']
            allboxes.append({"image":sample['image'],"box":[[round(float(x),2),round(float(y),2)] for x,y in poly],"text":d['text'],"confidence":d['confidence'],"cell":{"day":c[0],"period":c[1]} if c else None})
        records.append({"image":sample['image'],"augmentations":sample['transform'],"inferenceMs":round(elapsed,2),"raw":raw,"oracleDiagnostic":oracle,"recognizedWeekdayAnchors":da,"recognizedPeriodAnchors":pa,"mappingAvailable":da>=2 and pa>=2,"fieldCounts":field_counts,"mergedTextCorrect":merge_correct,"mergedTextTotal":len(merge_texts)})
        print(f"{sample['image']}: raw={raw['correct']+raw['emptyCorrect']}/30 oracle={oracle['correct']+oracle['emptyCorrect']}/30 anchors={da}/5,{pa}/6")
    import rapidocr_onnxruntime
    model_root=Path(rapidocr_onnxruntime.__file__).parent/'models'
    model_sizes={}
    for p in model_root.glob('*.onnx'):
        model_hashes[p.name]=hashlib.sha256(p.read_bytes()).hexdigest(); model_sizes[p.name]=p.stat().st_size
    occupied_total=sum(len(s['occupied']) for s in truth); empty_total=sum(s['emptyCells'] for s in truth); n=len(records)
    def aggregate(key):
        return {name:sum(r[key][name] for r in records) for name in ('correct','recognitionWrong','layoutWrong','detectionMissed','detected','emptyCorrect','emptyFalsePositive')}
    raw=aggregate('raw'); oracle=aggregate('oracleDiagnostic')
    field_totals={}
    for record in records:
        for name,(ok,total) in record['fieldCounts'].items():
            pair=field_totals.setdefault(name,[0,0]); pair[0]+=ok; pair[1]+=total
    merged_correct=sum(r['mergedTextCorrect'] for r in records); merged_total=sum(r['mergedTextTotal'] for r in records)
    def metrics(x):
        return {**x,"occupiedTotal":occupied_total,"emptyTotal":empty_total,"occupiedExactAccuracy":x['correct']/occupied_total,"occupiedDetectionRecall":x['detected']/occupied_total,"recognitionAccuracyAmongDetected":x['correct']/x['detected'] if x['detected'] else 0,"emptyAccuracy":x['emptyCorrect']/empty_total,"allCellAccuracy":(x['correct']+x['emptyCorrect'])/(n*30)}
    summary={"engine":"RapidOCR ONNXRuntime CPU","engineVersion":importlib.metadata.version('rapidocr-onnxruntime'),"runtimeVersions":{name:importlib.metadata.version(pkg) for name,pkg in (("onnxruntime","onnxruntime"),("numpy","numpy"),("Pillow","pillow"),("OpenCV","opencv-python-headless"))},"threads":{"intraOp":2,"interOp":1},"model":"PP-OCRv4 Chinese mobile det/rec + cls","datasetImages":n,"totalGridCells":n*30,"prediction":"rawImageHeaderInference","rawEndToEnd":metrics(raw),"oracleGeometryDiagnosticOnly":metrics(oracle),"richFieldStringRecognitionAnywhereInImage":{name:{"correct":ok,"total":total,"accuracy":ok/total if total else 0} for name,(ok,total) in field_totals.items()},"mergedCourseText":{"correct":merged_correct,"total":merged_total,"accuracy":merged_correct/merged_total if merged_total else 0,"scope":"text exactness only; no merged boundary reconstruction scored"},"meanInferenceMs":total_ms/n,"totalInferenceMs":total_ms,"wallSecondsIncludingModelLoadAndScoring":time.perf_counter()-run_start,"peakRssBytes":resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024,"modelBytes":model_sizes,"meanWeekdayAnchors":day_anchor_count/n,"meanPeriodAnchors":period_anchor_count/n,"samplesWithInferredMapping":sum(r['recognizedWeekdayAnchors']>=2 and r['recognizedPeriodAnchors']>=2 for r in records),"modelSha256":model_hashes,"samples":records}
    (out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'ocr-boxes.json').write_text(json.dumps({"schema":"ocr-boxes-v1","engine":summary['engine'],"mapping":"OCR-detected weekday and period anchors; no truth geometry","samples":allboxes},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('samples','modelSha256')},ensure_ascii=False,indent=2))
if __name__=='__main__': main()
