# ML Kit text recognition รองรับหลายชุดอักษร (ละติน จีน ญี่ปุ่น เกาหลี เทวนาครี)
# ปลั๊กอินอ้างถึงคลาสของทุกชุด แต่เราใส่มาเฉพาะละตินเพราะอ่านแค่ตัวเลขบนเรือนไมล์
# ถ้าไม่บอก R8 ให้ข้ามคลาสที่ไม่ได้ใส่มา มันจะหยุด build ทั้งที่โค้ดส่วนนั้นไม่มีวันถูกเรียก
#
# ถ้าวันหลังต้องอ่านอักษรอื่น ให้เพิ่ม dependency ของชุดนั้นแทนการลบบรรทัดพวกนี้
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
