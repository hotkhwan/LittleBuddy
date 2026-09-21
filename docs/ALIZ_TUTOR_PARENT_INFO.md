# Aliz Tutor — in-app "Privacy information" text

Owner: Agent G (privacy). Consumer: Agent F's Parent Corner row "Privacy
information". Plain language, no links, no prices, nothing addressed to a
child. The English block is 113 words; keep it at or under 120. The Thai block is a
helper for Thai-speaking parents, not a legal translation.

Both blocks must stay true. If the cloud tutor is ever enabled in a build, this
text must change in the same commit (see `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md`,
gate condition G13).

## English (show as-is)

Learn with Aliz runs on this device. Lessons, pictures and Aliz's voice are
built into the app. During a lesson the device's own speech recognition
listens for your child's answers and stops when the lesson ends. Nothing is
recorded, saved or sent anywhere: no audio, no words your child says, no name,
no location.

The app keeps only stars, lesson progress and today's tutor minutes, stored on
this device. You can erase them from Parent Corner at any time.

The online AI tutor is switched off in this build. It cannot be turned on from
the app. If a future version offers it, we will ask a parent first and explain
exactly what would be shared.

## Thai helper (แสดงใต้ข้อความภาษาอังกฤษ)

เรียนกับอลิซทำงานบนเครื่องนี้ทั้งหมด บทเรียน รูปภาพ และเสียงของอลิซถูกบรรจุมาในแอป
ระหว่างบทเรียน ระบบรู้จำเสียงของตัวเครื่องจะฟังคำตอบของลูก และหยุดฟังเมื่อจบบทเรียน
ไม่มีการบันทึกเสียง ไม่เก็บคำที่ลูกพูด ไม่ส่งข้อมูลใด ๆ ออกไป ไม่มีชื่อ ไม่มีตำแหน่งที่อยู่

แอปเก็บเพียงดาว ความคืบหน้าของบทเรียน และเวลาเรียนของวันนี้ไว้ในเครื่องนี้เท่านั้น
ผู้ปกครองลบได้ทุกเมื่อจากมุมผู้ปกครอง

ครูสอนออนไลน์ (AI) ปิดอยู่ในเวอร์ชันนี้ และเปิดจากในแอปไม่ได้
หากเวอร์ชันในอนาคตมีฟีเจอร์นี้ เราจะขออนุญาตผู้ปกครองก่อน และอธิบายให้ชัดเจนว่าจะแบ่งปันข้อมูลอะไรบ้าง

## Rules for whoever renders it

- Behind the parental gate only (3 s hold, unchanged).
- Static label; no button, no link, no "learn more".
- Do not shorten the sentence "The online AI tutor is switched off in this
  build." That sentence is the claim the guards in
  `game/tests/cases/test_tutor_privacy_guards.gd` and
  `test_tutor_flags.gd` keep true.
