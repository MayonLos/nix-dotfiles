# `timetable.json` v1

This document is the shared Android/desktop contract. Files are UTF-8 JSON with a `.json` extension. Unknown properties are rejected by the reference Kotlin codec; producers should emit only documented fields. `format` and `version` are required identifiers and currently equal `timetable` and `1`.

```json
{
  "format": "timetable",
  "version": 1,
  "semester": {
    "id": "2026-fall",
    "name": "2026 秋季学期",
    "startDate": "2026-09-07",
    "totalWeeks": 18,
    "timeZone": "Asia/Shanghai",
    "timeSlots": [
      { "period": 1, "start": "08:00", "end": "08:45" },
      { "period": 2, "start": "08:55", "end": "09:40" }
    ]
  },
  "courses": [
    {
      "id": "course-001",
      "name": "高等数学",
      "teacher": "王老师",
      "classroom": "教 1-203",
      "weekday": 1,
      "periodStart": 1,
      "periodEnd": 2,
      "weeks": [1, 3, 5, 7],
      "color": "#61AFEF",
      "notes": "带作业册"
    }
  ]
}
```

## Fields and validation

- `semester.startDate` is the Monday of teaching week 1, in `YYYY-MM-DD` form. Calendar week `n` derives from this date plus `n - 1` weeks.
- `semester.totalWeeks` is an integer from 1 through 60. Week numbers are one-based.
- `semester.timeZone` is an IANA time zone identifier. Day/time conversion uses this zone.
- Each `timeSlots` item defines one numbered class period. Periods are positive, unique, use local `HH:mm`, and may not overlap.
- `course.weekday` uses ISO numbering: Monday=1 through Sunday=7. `periodStart` and `periodEnd` are inclusive and must refer to defined periods.
- `weeks` is an explicit nonempty set of week numbers within the semester. An empty list does not mean every week; use `1..totalWeeks` explicitly.
- Optional `teacher`, `classroom`, `color`, and `notes` may be omitted. `color` uses `#RRGGBB`.
- Semester and course IDs match `[A-Za-z0-9_-]{1,80}`. Course IDs must be unique within one timetable. They are case-sensitive stable identifiers used for future sync and ICS event grouping; UUIDs are suitable. Names are display text and are not identities.
- Producers emit `weeks` in increasing order without duplicates. The reference encoder sorts week sets. Every period in the inclusive `periodStart..periodEnd` range must exist in `timeSlots`, including interior periods.
- Optional text may be omitted or null; the reference encoder omits null fields. Unknown keys or unsupported versions are rejected, and the source document must be retained for the user.

## Week expressions

The import UI may accept Chinese expressions and persist their expanded integer set. The JVM core understands forms such as `1-16周`, `1-16周(单)`, `2-16周（双）`, `1,3,5周`, and `1、3、5周`. The parser rejects reversed or out-of-semester ranges rather than clipping them.

## Calendar exchange

ICS export creates one `VEVENT` for each active course week. It writes ordinary `SUMMARY`, `LOCATION`, and `DESCRIPTION` plus `X-TIMETABLE-*` properties for course ID, teacher, notes, week, weekday and period bounds, so round-trip retains week sets and period identity. External ICS `DESCRIPTION` is imported as a note; it is never guessed to be a teacher. UTF-8 property folding and RFC text escaping are applied.

ICS export writes UTC `DTSTART`/`DTEND` values (`Z`) and retains the semester IANA zone in `X-WR-TIMEZONE`, so no `VTIMEZONE` block is needed. ICS import supports explicit timetable properties and external weekly recurrence with `FREQ=WEEKLY`, optional `INTERVAL`, `BYDAY`, and date-form `UNTIL` (`YYYYMMDD`, accepted as a compatibility extension). Other `RRULE` fields, including `COUNT`, datetime `UNTIL`, `WKST`, `RDATE`, and `EXDATE`, fail explicitly. External events without timetable period metadata must match a configured period start/end time exactly; otherwise import reports an error. All-day events cannot represent class periods and are rejected.

## Compatibility policy

A future incompatible schema increments `version`. A consumer that sees an unsupported version must preserve the source file and report that it cannot import it. Sync implementations compare IDs and versions; no cloud service is implied by this file format.
