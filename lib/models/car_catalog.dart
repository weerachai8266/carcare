/// แปลงข้อความเป็น id ที่อ่านออกและคงที่ เช่น "toyota-Corolla Cross" → "toyota-corolla-cross"
///
/// ต้องคงที่ข้ามเครื่องและข้ามเวอร์ชัน เพราะเซิร์ฟเวอร์ใช้ id นี้จับกลุ่มสถิติของรุ่นเดียวกัน
/// ตัวอักษรที่ไม่ใช่ a-z 0-9 (รวมภาษาไทย) จะกลายเป็นขีด แล้วยุบขีดซ้ำ
///
/// อยู่ในไฟล์โมเดลเพื่อให้สคริปต์ tool/export_catalog_sql.dart เรียกใช้ได้
/// โดยไม่ต้องดึง sqflite (ซึ่งรันนอก Flutter ไม่ได้) เข้ามาด้วย
String catalogSlug(String input) {
  final lowered = input.toLowerCase();
  final buffer = StringBuffer();
  var lastWasDash = false;

  for (final unit in lowered.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLetter = unit >= 0x61 && unit <= 0x7a;
    if (isDigit || isLetter) {
      buffer.writeCharCode(unit);
      lastWasDash = false;
    } else if (!lastWasDash) {
      buffer.write('-');
      lastWasDash = true;
    }
  }

  return buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
}

/// ยี่ห้อรถ
///
/// [id] เป็น slug ที่คงที่ (เช่น `toyota`) ไม่ใช่ UUID เพื่อให้ทุกเครื่อง
/// และเซิร์ฟเวอร์อ้างถึงยี่ห้อเดียวกันด้วย id เดียวกัน — จำเป็นต่อการรวมสถิติข้ามผู้ใช้
/// ส่วนยี่ห้อที่ผู้ใช้เพิ่มเอง ([isCustom]) จะใช้ UUID เพราะยังไม่มีใน catalog กลาง
class CarMake {
  final String id;
  final String name;

  /// ชื่อไทย ใช้ช่วยค้นหา เช่น พิมพ์ "โตโยต้า" ต้องเจอ Toyota
  final String? nameTh;

  final int sortOrder;
  final bool isCustom;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const CarMake({
    required this.id,
    required this.name,
    this.nameTh,
    this.sortOrder = 0,
    this.isCustom = false,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
  });

  /// ข้อความที่ใช้เทียบตอนค้นหา รวมชื่อไทยเข้าไปด้วย
  String get searchText => '$name ${nameTh ?? ''}'.toLowerCase();

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'name_th': nameTh,
        'sort_order': sortOrder,
        'is_custom': isCustom ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory CarMake.fromMap(Map<String, Object?> m) => CarMake(
        id: m['id'] as String,
        name: m['name'] as String,
        nameTh: m['name_th'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
        isCustom: (m['is_custom'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}

/// รุ่นรถของยี่ห้อหนึ่ง
class CarModel {
  final String id;
  final String makeId;
  final String name;

  /// ประเภทตัวถัง เช่น เก๋ง, กระบะ, SUV — ใช้จัดกลุ่มในหน้าเลือกรุ่น
  final String? bodyType;

  final int sortOrder;
  final bool isCustom;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const CarModel({
    required this.id,
    required this.makeId,
    required this.name,
    this.bodyType,
    this.sortOrder = 0,
    this.isCustom = false,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'make_id': makeId,
        'name': name,
        'body_type': bodyType,
        'sort_order': sortOrder,
        'is_custom': isCustom ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory CarModel.fromMap(Map<String, Object?> m) => CarModel(
        id: m['id'] as String,
        makeId: m['make_id'] as String,
        name: m['name'] as String,
        bodyType: m['body_type'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
        isCustom: (m['is_custom'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}

/// ประเภทตัวถังที่ใช้ในแคตตาล็อก
class BodyType {
  BodyType._();

  static const sedan = 'เก๋ง';
  static const hatchback = 'แฮทช์แบ็ก';
  static const suv = 'SUV';
  static const pickup = 'กระบะ';
  static const mpv = 'MPV';
  static const van = 'รถตู้';
  static const sports = 'สปอร์ต';

  /// ลำดับที่ใช้จัดกลุ่มในหน้าเลือกรุ่น เรียงตามความนิยมในไทย
  static const order = [sedan, hatchback, suv, pickup, mpv, van, sports];
}

/// รายการยี่ห้อ/รุ่นตั้งต้นสำหรับ seed ลงฐานข้อมูล
///
/// ขอบเขต: รถยนต์ที่ทำตลาดในไทยตั้งแต่ปี 2020 เป็นต้นมา
/// ไม่ได้ครอบคลุมทุกรุ่นย่อย และไม่ได้ลงรายละเอียดปีที่เลิกขาย
/// เพราะจุดประสงค์คือให้ผู้ใช้เลือกได้เร็ว ไม่ใช่เป็นฐานข้อมูลรถที่สมบูรณ์
/// รุ่นที่ไม่มีในนี้ผู้ใช้เพิ่มเองได้ และรุ่นที่เพิ่มเองจะถูกส่งขึ้นเซิร์ฟเวอร์
/// เพื่อนำไปเติมแคตตาล็อกกลางในภายหลัง
class MakeSeed {
  final String id;
  final String name;
  final String nameTh;

  /// รุ่นแยกตามประเภทตัวถัง
  final Map<String, List<String>> models;

  const MakeSeed(this.id, this.name, this.nameTh, this.models);

  static const List<MakeSeed> all = [
    MakeSeed('toyota', 'Toyota', 'โตโยต้า', {
      BodyType.sedan: ['Yaris Ativ', 'Vios', 'Corolla Altis', 'Camry', 'Prius'],
      BodyType.hatchback: ['Yaris'],
      BodyType.suv: [
        'Corolla Cross',
        'Yaris Cross',
        'C-HR',
        'Fortuner',
        'Raize',
        'bZ4X',
      ],
      BodyType.pickup: ['Hilux Revo', 'Hilux Champ'],
      BodyType.mpv: [
        'Innova Zenix',
        'Innova Crysta',
        'Veloz',
        'Avanza',
        'Sienta',
        'Alphard',
        'Vellfire',
        'Majesty',
      ],
      BodyType.van: ['Commuter', 'Hiace'],
      BodyType.sports: ['GR86', 'GR Supra', 'GR Yaris'],
    }),
    MakeSeed('honda', 'Honda', 'ฮอนด้า', {
      BodyType.sedan: ['City', 'Civic', 'Accord'],
      BodyType.hatchback: ['City Hatchback', 'Jazz', 'Civic Hatchback'],
      BodyType.suv: ['HR-V', 'CR-V', 'WR-V', 'e:N1', 'ZR-V'],
      BodyType.mpv: ['BR-V', 'Odyssey', 'Mobilio', 'Stepwgn'],
    }),
    MakeSeed('isuzu', 'Isuzu', 'อีซูซุ', {
      BodyType.pickup: ['D-Max', 'D-Max V-Cross', 'D-Max Spark'],
      BodyType.suv: ['MU-X'],
    }),
    MakeSeed('mitsubishi', 'Mitsubishi', 'มิตซูบิชิ', {
      BodyType.sedan: ['Attrage'],
      BodyType.hatchback: ['Mirage'],
      BodyType.suv: ['Pajero Sport', 'Outlander PHEV', 'Xforce'],
      BodyType.pickup: ['Triton'],
      BodyType.mpv: ['Xpander', 'Xpander Cross'],
    }),
    MakeSeed('nissan', 'Nissan', 'นิสสัน', {
      BodyType.sedan: ['Almera', 'Sylphy', 'Teana'],
      BodyType.hatchback: ['Note', 'March', 'Leaf'],
      BodyType.suv: ['Kicks e-POWER', 'Terra', 'X-Trail'],
      BodyType.pickup: ['Navara'],
    }),
    MakeSeed('mazda', 'Mazda', 'มาสด้า', {
      BodyType.sedan: ['Mazda2 Sedan', 'Mazda3 Sedan'],
      BodyType.hatchback: ['Mazda2', 'Mazda3'],
      BodyType.suv: ['CX-3', 'CX-30', 'CX-5', 'CX-8', 'CX-60'],
      BodyType.pickup: ['BT-50'],
      BodyType.sports: ['MX-5'],
    }),
    MakeSeed('ford', 'Ford', 'ฟอร์ด', {
      BodyType.pickup: ['Ranger', 'Ranger Raptor'],
      BodyType.suv: ['Everest', 'Territory'],
      BodyType.sports: ['Mustang'],
    }),
    MakeSeed('mg', 'MG', 'เอ็มจี', {
      BodyType.sedan: ['MG5', 'MG7'],
      BodyType.hatchback: ['MG3', 'MG4 Electric'],
      BodyType.suv: [
        'MG ZS',
        'MG ZS EV',
        'MG HS',
        'MG VS HEV',
        'MG EP',
        'MG ES',
        'MG S5 EV',
      ],
      BodyType.pickup: ['MG Extender'],
      BodyType.mpv: ['MG Maxus 9'],
      BodyType.sports: ['MG Cyberster'],
    }),
    MakeSeed('byd', 'BYD', 'บีวายดี', {
      BodyType.sedan: ['Seal'],
      BodyType.hatchback: ['Dolphin'],
      BodyType.suv: ['Atto 3', 'Sealion 6 DM-i', 'Sealion 7', 'Atto 1'],
      BodyType.mpv: ['M6'],
    }),
    MakeSeed('suzuki', 'Suzuki', 'ซูซูกิ', {
      BodyType.sedan: ['Ciaz'],
      BodyType.hatchback: ['Swift', 'Celerio'],
      BodyType.suv: ['Jimny', 'Fronx'],
      BodyType.mpv: ['Ertiga', 'XL7'],
      BodyType.pickup: ['Carry'],
    }),
    MakeSeed('hyundai', 'Hyundai', 'ฮุนได', {
      BodyType.suv: ['Creta', 'Ioniq 5', 'Tucson'],
      BodyType.sedan: ['Ioniq 6'],
      BodyType.mpv: ['Staria', 'H-1', 'Stargazer', 'Custin'],
    }),
    MakeSeed('kia', 'Kia', 'เกีย', {
      BodyType.suv: ['Seltos', 'Sonet', 'Sorento', 'EV6', 'EV9', 'EV5'],
      BodyType.mpv: ['Carnival'],
    }),
    MakeSeed('gwm', 'GWM', 'เกรท วอลล์ มอเตอร์', {
      BodyType.suv: [
        'Haval H6',
        'Haval Jolion',
        'Haval H6 PHEV',
        'Tank 300',
        'Tank 500',
        'Ora Good Cat',
      ],
      BodyType.pickup: ['Poer', 'Cannon Alpha'],
    }),
    MakeSeed('tesla', 'Tesla', 'เทสลา', {
      BodyType.sedan: ['Model 3', 'Model S'],
      BodyType.suv: ['Model Y', 'Model X'],
    }),
    MakeSeed('neta', 'NETA', 'เนต้า', {
      BodyType.hatchback: ['NETA V', 'NETA V-II'],
      BodyType.suv: ['NETA X'],
      BodyType.sedan: ['NETA S'],
    }),
    MakeSeed('aion', 'AION', 'ไอออน', {
      BodyType.suv: ['AION Y Plus', 'AION V', 'Hyptec HT'],
      BodyType.sedan: ['AION ES'],
    }),
    MakeSeed('changan', 'Changan', 'ฉางอาน', {
      BodyType.suv: ['Deepal S07', 'Deepal S05', 'CS55 Plus', 'Lumin'],
      BodyType.sedan: ['Deepal L07'],
      BodyType.pickup: ['Hunter'],
    }),
    MakeSeed('lexus', 'Lexus', 'เล็กซัส', {
      BodyType.sedan: ['ES', 'IS', 'LS'],
      BodyType.suv: ['UX', 'NX', 'RX', 'LX', 'RZ'],
      BodyType.mpv: ['LM'],
    }),
    MakeSeed('mercedes-benz', 'Mercedes-Benz', 'เมอร์เซเดส-เบนซ์', {
      BodyType.sedan: ['A-Class', 'C-Class', 'E-Class', 'S-Class', 'CLA'],
      BodyType.suv: ['GLA', 'GLB', 'GLC', 'GLE', 'GLS', 'EQB', 'EQE SUV'],
    }),
    MakeSeed('bmw', 'BMW', 'บีเอ็มดับเบิลยู', {
      BodyType.sedan: ['Series 3', 'Series 5', 'Series 7', 'i4', 'i5', 'i7'],
      BodyType.suv: ['X1', 'X3', 'X4', 'X5', 'X7', 'iX', 'iX1', 'iX3'],
      BodyType.sports: ['Z4', 'Series 2 Coupe', 'Series 4'],
    }),
    MakeSeed('volvo', 'Volvo', 'วอลโว่', {
      BodyType.sedan: ['S60', 'S90'],
      BodyType.suv: ['XC40', 'XC60', 'XC90', 'C40', 'EX30', 'EX90'],
    }),
    MakeSeed('subaru', 'Subaru', 'ซูบารุ', {
      BodyType.suv: ['Forester', 'XV', 'Crosstrek', 'Outback'],
      BodyType.sedan: ['WRX'],
      BodyType.sports: ['BRZ'],
    }),
    MakeSeed('volkswagen', 'Volkswagen', 'โฟล์คสวาเกน', {
      BodyType.van: ['Caravelle', 'ID. Buzz'],
      BodyType.suv: ['T-Cross', 'Tiguan'],
    }),
    MakeSeed('audi', 'Audi', 'ออดี้', {
      BodyType.sedan: ['A4', 'A5', 'A6', 'A7', 'e-tron GT'],
      BodyType.suv: ['Q3', 'Q5', 'Q7', 'Q8', 'Q4 e-tron', 'Q8 e-tron'],
    }),
    MakeSeed('porsche', 'Porsche', 'ปอร์เช่', {
      BodyType.suv: ['Macan', 'Cayenne'],
      BodyType.sedan: ['Panamera', 'Taycan'],
      BodyType.sports: ['911', '718 Cayman', '718 Boxster'],
    }),
    MakeSeed('chevrolet', 'Chevrolet', 'เชฟโรเลต', {
      BodyType.pickup: ['Colorado'],
      BodyType.suv: ['Trailblazer', 'Captiva'],
    }),
    MakeSeed('jaecoo', 'JAECOO', 'เจคู', {
      BodyType.suv: ['Jaecoo 6', 'Jaecoo 7', 'Jaecoo 8'],
    }),
    MakeSeed('omoda', 'OMODA', 'โอโมดา', {
      BodyType.suv: ['Omoda C5', 'Omoda 5', 'Omoda C7'],
    }),
    MakeSeed('deepal', 'Deepal', 'ดีพัล', {
      BodyType.suv: ['Deepal S07'],
      BodyType.sedan: ['Deepal L07'],
    }),
    MakeSeed('xpeng', 'XPeng', 'เอ็กซ์เผิง', {
      BodyType.suv: ['G6', 'G9'],
      BodyType.mpv: ['X9'],
    }),
    MakeSeed('zeekr', 'Zeekr', 'ซีเคอร์', {
      BodyType.suv: ['Zeekr X', 'Zeekr 7X'],
      BodyType.mpv: ['Zeekr 009'],
    }),
    MakeSeed('mini', 'MINI', 'มินิ', {
      BodyType.hatchback: ['Cooper', 'Cooper SE'],
      BodyType.suv: ['Countryman', 'Aceman'],
    }),
    MakeSeed('land-rover', 'Land Rover', 'แลนด์โรเวอร์', {
      BodyType.suv: ['Defender', 'Discovery', 'Range Rover', 'Range Rover Evoque'],
    }),
    MakeSeed('foton', 'Foton', 'โฟตอน', {
      BodyType.pickup: ['Tunland G7', 'Tunland V7'],
    }),
    MakeSeed('jac', 'JAC', 'เจเอซี', {
      BodyType.pickup: ['T9'],
      BodyType.suv: ['JS4'],
    }),
  ];
}
