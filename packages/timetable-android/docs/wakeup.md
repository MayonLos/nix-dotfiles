# WakeUp compatibility research (2026-10-30)

## What is confirmed from source

WakeUp's official guides confirm Android can import an online share key or a locally exported backup, but the official docs do not define a machine-readable schema or API: [official import guide](https://www.wakeup.fun/doc/import_schedule.html), [file import guide](https://www.wakeup.fun/doc/import_from_file.html). The privacy policy confirms those product functions: [WakeUp privacy policy](https://www.wakeup.fun/policy.html).

The line-based `.wakeup_schedule` parser is grounded in two public converters:

- [`Linho1219/xiaoaischedule-automation`, `src/main.ts#L84-L98`](https://github.com/Linho1219/xiaoaischedule-automation/blob/main/src/main.ts#L84-L98) parses exactly five JSON lines as `TimeMetadata`, `TimeEntry[]`, `ScheduleMetadata`, `CourseEntry[]`, `ClassEntry[]`.
- [`Pimeng/classtable`, `utils/importParser.js#L1-L88`](https://github.com/Pimeng/classtable/blob/main/utils/importParser.js#L1-L88) identifies the four timetable-bearing chunks by shape (`timeTable`, `settings`, `courses`, `schedule`), recurses through `data`/`shareData`, and tolerates an optional extra metadata chunk. The same repository's [`apps/import.js#L167-L196`](https://github.com/Pimeng/classtable/blob/main/apps/import.js#L167-L196) consumes WakeUp share text. Its API wrapper at [`apps/import.js#L259-L279`](https://github.com/Pimeng/classtable/blob/main/apps/import.js#L259-L279) calls a configured authenticated proxy `/share?shareCode=...` and wraps `data.shareData` as `{status:1,message:"success",data:...}`.

The converter source defines these records:

- `TimeMetadata`: `courseLen`, `id`, `name`, `sameBreakLen`, `sameLen`, `theBreakLen`.
- `TimeEntry`: `endTime`, `node`, `startTime`, `timeTable`.
- `ScheduleMetadata` / `settings`: `id`, `maxWeek`, `nodes`, `showOtherWeekCourse`, `showSat`, `showSun`, `sundayFirst`, `startDate`, `tableName`, `timeTable`.
- `CourseEntry`: `courseName`, `credit`, `id`, `note`, `tableId`.
- `ClassEntry` / `schedule`: `day`, `endWeek`, `id`, `level`, `ownTime`, `room`, `startNode`, `startWeek`, `step`, `tableId`, `teacher`, `type`.

`ClassEntry.id` joins to `CourseEntry.id`; a course base can have several meetings. `type` is 0 every week, 1 odd weeks, and 2 even weeks. Time rows are limited by `ScheduleMetadata.nodes`. The source converter silently filters `ownTime` entries; this core explicitly rejects them because custom times cannot be represented by period indices without losing information.

Fixtures in [`fixtures/wakeup/`](../fixtures/wakeup/) are self-authored synthetic data only. `backup-lines.jsonl` checks the five-record arrangement, base/meeting join, parity expansion, and `ownTime` rejection. `share-response.json` checks the share envelope with the four-key object form. `legacy-share-candidate.json` exercises an older `courseList/timeList` shape reported in a community note; that shape is provisional and separate from the confirmed converter schema.

## Share-key extraction and network boundary

Pimeng's public importer matches the canonical WakeUp share message and captures arbitrary quoted content inside `分享口令为「...」`; it does not establish that a token must be 32 hexadecimal characters. `WakeUpParser.extractShareKey` follows the quoted form and retains a 32-hex fallback. It does not resolve URLs or perform network requests.

The public Koishi format note describes an older `GET https://i.wakeup.fun/share_schedule/get?key=...` interface and a legacy `courseList/timeList` payload: [community reverse-engineering note](https://github.com/VincentZyuApps/koishi-plugin-course-schedule/blob/main/docs/formats/wakeup-schedule.md). That note is not official and does not prove that the endpoint still works. Current Pimeng code uses its configured `WAKEUP_URL` authenticated proxy instead. No endpoint was contacted, no key was queried, and no real timetable was fetched.

## Parser policy and limitations

`WakeUpParser.parseBackup` selects the record arrays by their source-level fields and accepts the source's optional extra `TimeMetadata` record. `parseShareResponse` accepts the observed status/data envelope, recursively handles `data` and `shareData`, and supports the four-key object or a JSON-lines string. The old community `courseList/timeList` shape remains a best-effort candidate adapter.

The confirmed four/five-record order also supports empty course and meeting arrays. Malformed JSON records are rejected, rather than skipped during a partial import. The core validates dates, period rows, week ranges, parity and linked IDs. It assumes `Asia/Shanghai` because the observed WakeUp records contain no time-zone field, and normalizes `startDate` to the Monday of its teaching week to satisfy the shared v1 contract. Unsupported `ownTime` meetings fail with a clear message; they are never omitted silently.
