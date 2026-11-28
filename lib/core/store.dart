import 'service_data.dart';
import 'inverter_history.dart';
import 'appliance_data.dart';
import 'backend_service.dart';
import 'estimator_data.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calc.dart';
import 'sun.dart';
import 'i18n.dart';
import 'geo.dart';
import 'solar_data.dart';
import 'tariff.dart';
export 'store_consts.dart';

class Site {
  String city, label;
  double lat, lon, kwp, tariff;
  bool auto;
  Site({
    this.city = 'Hyderabad',
    this.label = 'Telangana, India',
    this.lat = 17.385,
    this.lon = 78.4867,
    this.kwp = 3.74,
    this.tariff = 7.2,
    this.auto = true,
  });

  Map<String, dynamic> toJson() =>
      {'city': city, 'label': label, 'lat': lat, 'lon': lon, 'kwp': kwp, 'tariff': tariff, 'auto': auto};

  factory Site.fromJson(Map<String, dynamic> j) {
    final d = Site();
    double n(String k, double def) => (j[k] is num) ? (j[k] as num).toDouble() : def;
    return Site(
      city: (j['city'] as String?) ?? d.city,
      label: (j['label'] as String?) ?? d.label,
      lat: n('lat', d.lat),
      lon: n('lon', d.lon),
      kwp: n('kwp', d.kwp),
      tariff: n('tariff', d.tariff),
      auto: (j['auto'] as bool?) ?? true,
    );
  }
}

/// Owner and plant details (Profile dialog). System capacity lives in [Site.kwp].
class Profile {
  String name, serviceNo, mobile, pin, email, address;
  String roofType, panel, inverter, commission, helpline;
  double roofSqft;
  int warranty;
  Profile({
    this.name = '',
    this.serviceNo = '',
    this.mobile = '',
    this.pin = '',
    this.email = '',
    this.address = '',
    this.roofType = 'rcc',
    this.panel = '',
    this.inverter = '',
    this.commission = '',
    this.helpline = '',
    this.roofSqft = 700,
    this.warranty = 25,
  });

  Map<String, dynamic> toJson() => {
        'name': name, 'serviceNo': serviceNo, 'mobile': mobile, 'pin': pin, 'email': email,
        'address': address, 'roofType': roofType, 'panel': panel, 'inverter': inverter,
        'commission': commission, 'helpline': helpline, 'roofSqft': roofSqft, 'warranty': warranty,
      };

  factory Profile.fromJson(Map<String, dynamic> j) {
    final d = Profile();
    String t(String k, String def) => (j[k] as String?) ?? def;
    return Profile(
      name: t('name', ''), serviceNo: t('serviceNo', ''), mobile: t('mobile', ''), pin: t('pin', ''),
      email: t('email', ''), address: t('address', ''), roofType: t('roofType', d.roofType),
      panel: t('panel', ''), inverter: t('inverter', ''), commission: t('commission', ''), helpline: t('helpline', ''),
      roofSqft: (j['roofSqft'] as num?)?.toDouble() ?? d.roofSqft,
      warranty: (j['warranty'] as num?)?.toInt() ?? d.warranty,
    );
  }

  /// Commission date parsed from dd/mm/yyyy, or null.
  DateTime? get commissionDate {
    final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(commission.trim());
    if (m == null) return null;
    try {
      return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    } catch (_) {
      return null;
    }
  }

  DateTime? get warrantyEnds {
    final c = commissionDate;
    return c == null ? null : DateTime(c.year + warranty, c.month, c.day);
  }
}

/// User preferences (Settings dialog).
class Prefs {
  String lang, stateId, discomId, category;
  bool? dark; // null = follow the device
  bool battery, autoSync, cloudAlerts;
  int dustDays;
  double textScale; // user text/screen size on top of the automatic fit (1.0 = auto)
  String backendUrl; // optional Render / Cloud Run proxy URL for live DISCOM & Inverter portal sync

  Prefs({
    this.lang = 'en',
    this.stateId = 'telangana',
    this.discomId = '',
    this.category = 'domestic',
    this.dark,
    this.battery = false,
    this.autoSync = true,
    this.cloudAlerts = true,
    this.dustDays = 30,
    this.textScale = 1.0,
    this.backendUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'lang': lang, 'stateId': stateId, 'discomId': discomId, 'category': category, 'dark': dark,
        'battery': battery, 'autoSync': autoSync, 'cloudAlerts': cloudAlerts, 'dustDays': dustDays,
        'textScale': textScale, 'backendUrl': backendUrl,
      };

  factory Prefs.fromJson(Map<String, dynamic> j) {
    final d = Prefs();
    return Prefs(
      lang: (j['lang'] as String?) ?? d.lang,
      stateId: (j['stateId'] as String?) ?? d.stateId,
      discomId: (j['discomId'] as String?) ?? '',
      category: (j['category'] as String?) ?? d.category,
      dark: j['dark'] as bool?,
      battery: (j['battery'] as bool?) ?? false,
      autoSync: (j['autoSync'] as bool?) ?? true,
      cloudAlerts: (j['cloudAlerts'] as bool?) ?? true,
      dustDays: (j['dustDays'] as num?)?.toInt() ?? 30,
      textScale: ((j['textScale'] as num?)?.toDouble() ?? 1.0).clamp(.8, 1.4),
      backendUrl: (j['backendUrl'] as String?) ?? '',
    );
  }
}

class Brand {
  String company, phone, note;
  Brand({
    this.company = 'Gensolar',
    this.phone = '',
    this.note = 'Estimate only. Final design, cost and subsidy subject to site survey and DISCOM approval.',
  });

  Map<String, dynamic> toJson() => {'company': company, 'phone': phone, 'note': note};

  factory Brand.fromJson(Map<String, dynamic> j) {
    final d = Brand();
    return Brand(
      company: (j['company'] as String?) ?? d.company,
      phone: (j['phone'] as String?) ?? d.phone,
      note: (j['note'] as String?) ?? d.note,
    );
  }
}

class Appliance {
  String id, name;
  double watts, hours;
  int qty, start;
  bool backup; // keep running on battery during a power cut
  Appliance({
    required this.id,
    required this.name,
    required this.watts,
    required this.qty,
    required this.hours,
    required this.start,
    this.backup = false,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'watts': watts, 'qty': qty, 'hours': hours, 'start': start, 'backup': backup};

  factory Appliance.fromJson(Map<String, dynamic> j) => Appliance(
        id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: (j['name'] as String?) ?? 'Appliance',
        watts: (j['watts'] as num?)?.toDouble() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        hours: (j['hours'] as num?)?.toDouble() ?? 0,
        start: (j['start'] as num?)?.toInt() ?? 0,
        backup: (j['backup'] as bool?) ?? false,
      );
}

class Customer {
  String usc, name, phone, address;
  Customer({this.usc = '', this.name = '', this.phone = '', this.address = ''});
  Map<String, dynamic> toJson() => {'usc': usc, 'name': name, 'phone': phone, 'address': address};
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        usc: (j['usc'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
      );
}

class SavedRecord {
  String id;
  int savedAt;
  Customer customer;
  EstimateInput input;
  SavedRecord({required this.id, required this.savedAt, required this.customer, required this.input});
  EstimateResult get result => calculate(input);
  Map<String, dynamic> toJson() =>
      {'id': id, 'savedAt': savedAt, 'customer': customer.toJson(), 'input': input.toJson()};
  factory SavedRecord.fromJson(Map<String, dynamic> j) => SavedRecord(
        id: (j['id'] as String?) ?? '',
        savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
        customer: Customer.fromJson((j['customer'] as Map?)?.cast<String, dynamic>() ?? {}),
        input: EstimateInput.fromJson((j['input'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
}

/// App-wide state with simple persistence in SharedPreferences.
class AppState extends ChangeNotifier {
  SharedPreferences? _p;
  Site site = Site();
  Brand brand = Brand();
  List<Appliance> appliances = [];
  List<SavedRecord> records = [];
  Profile profile = Profile();
  Prefs prefs = Prefs();
  TariffBook? book;
  Place? place;
  MonthlyPsh? monthly;
  DateTime? lastCleaned;
  List<ServiceEntry> services = [];
  WeatherNow? weather;
  Irradiance? irr;
  DateTime? lastSync;
  bool syncing = false;
  int tab = 0;
  ApplCfg appl = ApplCfg();
  Rates rates = const Rates();
  List<ApplRecord> applHistory = [];
  InverterConfig inverterCfg = InverterConfig();
  InverterSnapshot? inverterSnap;
  List<UscHistoryItem> uscHistory = [];
  List<InverterLoginItem> inverterLogins = [];

  /// Set by Appliance Analysis; the Estimator picks it up when it opens.
  EstimateInput? estimatePush;

  // estimator working state (kept when switching tabs)
  Customer customer = Customer();
  EstimateInput input = EstimateInput();
  EstimateResult? result;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final p = _p!;
      Map<String, dynamic>? obj(String k) {
        final s = p.getString(k);
        if (s == null) return null;
        final v = jsonDecode(s);
        return v is Map ? v.cast<String, dynamic>() : null;
      }

      List<dynamic>? list(String k) {
        final s = p.getString(k);
        if (s == null) return null;
        final v = jsonDecode(s);
        return v is List ? v : null;
      }

      final s = obj('site');
      if (s != null) site = Site.fromJson(s);
      final b = obj('brand');
      if (b != null) brand = Brand.fromJson(b);
      final a = list('appliances');
      if (a != null) {
        appliances = a.whereType<Map>().map((e) => Appliance.fromJson(e.cast<String, dynamic>())).toList();
      }
      final r = list('records');
      if (r != null) {
        records = r.whereType<Map>().map((e) => SavedRecord.fromJson(e.cast<String, dynamic>())).toList();
      }
      final sv = list('services');
      if (sv != null) services = sv.whereType<Map>().map((e) => ServiceEntry.fromJson(e.cast<String, dynamic>())).toList();
      final ap = obj('appl');
      if (ap != null) appl = ApplCfg.fromJson(ap);
      final rt = obj('appl_rates');
      if (rt != null) rates = Rates.fromJson(rt);
      final ah = list('appl_hist');
      if (ah != null) applHistory = ah.whereType<Map>().map((e) => ApplRecord.fromJson(e.cast<String, dynamic>())).toList();
      final ic = obj('inverter_cfg');
      if (ic != null) inverterCfg = InverterConfig.fromJson(ic);
      final isnp = obj('inverter_snap');
      if (isnp != null) inverterSnap = InverterSnapshot.fromJson(isnp);
      final il = list('inverter_logins');
      if (il != null) inverterLogins = il.whereType<Map>().map((e) => InverterLoginItem.fromJson(e.cast<String, dynamic>())).toList();
      final uh = list('usc_history');
      if (uh != null) uscHistory = uh.whereType<Map>().map((e) => UscHistoryItem.fromJson(e.cast<String, dynamic>())).toList();
      final pr = obj('profile');
      if (pr != null) profile = Profile.fromJson(pr);
      final pf = obj('prefs');
      if (pf != null) prefs = Prefs.fromJson(pf);
      final lc = p.getInt('lastCleaned');
      if (lc != null) lastCleaned = DateTime.fromMillisecondsSinceEpoch(lc);
      final ls = p.getInt('lastSync');
      if (ls != null) lastSync = DateTime.fromMillisecondsSinceEpoch(ls);
    } catch (_) {
      if (appliances.isEmpty) appliances = _defaultAppliances();
    }
    if (appliances.isEmpty && (_p?.getString('appliances') == null)) appliances = _defaultAppliances();
    site.auto = prefs.autoSync;
    await _loadTariffs();
    _syncDerived();
    notifyListeners();
  }

  Future<void> _loadTariffs() async {
    book = await TariffBook.load(
      cached: _p?.getString('tariffs'),
      onFresh: (raw) => _p?.setString('tariffs', raw),
    );
    if (prefs.discomId.isEmpty || !st.discoms.any((d) => d.id == prefs.discomId)) {
      prefs.discomId = st.discoms.first.id;
    }
  }

  List<Appliance> _defaultAppliances() {
    var i = 0;
    Appliance a(String n, double w, int q, double h, int s) =>
        Appliance(id: 'd${i++}', name: n, watts: w, qty: q, hours: h, start: s);
    return [
      a('Refrigerator', 120, 1, 24, 0),
      a('Air conditioner', 1500, 1, 6, 22),
      a('Ceiling fans', 60, 4, 10, 18),
      a('LED lights', 9, 8, 6, 18),
      a('Television', 100, 1, 4, 19),
      a('Water pump', 750, 1, 1, 7),
    ];
  }

  void _save(String k, Object v) => _p?.setString(k, jsonEncode(v));
  void saveSite() { _save('site', site.toJson()); notifyListeners(); }
  void saveBrand() { _save('brand', brand.toJson()); notifyListeners(); }
  void saveAppl() { _save('appl', appl.toJson()); notifyListeners(); }
  void saveRates() { _save('appl_rates', rates.toJson()); notifyListeners(); }

  void saveApplHistory() {
    if (applHistory.length > 100) applHistory = applHistory.sublist(0, 100);
    _save('appl_hist', applHistory.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void saveInverter() {
    _save('inverter_cfg', inverterCfg.toJson());
    if (inverterSnap != null) {
      _save('inverter_snap', inverterSnap!.toJson());
    } else {
      _p?.remove('inverter_snap');
    }
    notifyListeners();
  }

  /// One entry per account. A new login for the same account updates it, and a failed
  /// login keeps the last good data.
  void addInverterLogin(InverterLoginItem item) {
    final prev = inverterLogins.where((x) => x.key == item.key).firstOrNull;
    inverterLogins.removeWhere((x) => x.key == item.key);
    final keepSnap = item.snap ?? prev?.snap;
    final keepCfg = item.cfg ?? prev?.cfg;
    inverterLogins.insert(
      0,
      InverterLoginItem(
        at: item.at,
        brand: item.brand,
        authMode: item.authMode,
        account: item.account,
        ok: item.ok,
        message: item.message,
        cfg: keepCfg,
        snap: keepSnap,
      ),
    );
    if (inverterLogins.length > 30) inverterLogins = inverterLogins.sublist(0, 30);
    _save('inverter_logins', inverterLogins.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void clearInverter() {
    inverterSnap = null;
    _p?.remove('inverter_snap');
    notifyListeners();
  }

  void addUscHistory(UscHistoryItem item) {
    uscHistory.removeWhere((x) => x.usc == item.usc && x.stateId == item.stateId);
    uscHistory.insert(0, item);
    if (uscHistory.length > 20) uscHistory = uscHistory.sublist(0, 20);
    _save('usc_history', uscHistory.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void saveAppliances() { _save('appliances', appliances.map((e) => e.toJson()).toList()); notifyListeners(); }

  void saveServices() {
    services.sort((a, b) => b.date.compareTo(a.date));
    _save('services', services.map((e) => e.toJson()).toList());
    final cleans = services.where((e) => e.type == ServiceType.cleaning);
    if (cleans.isNotEmpty) {
      lastCleaned = cleans.first.date;
      _p?.setInt('lastCleaned', lastCleaned!.millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  void saveRecords() { _save('records', records.map((e) => e.toJson()).toList()); notifyListeners(); }
  void setTab(int i) { tab = i; notifyListeners(); }

  /// Estimator result feeds the Home dashboard (plant size and tariff).
  void publishEstimate(double kw, double tariff) {
    site.kwp = (kw * 100).round() / 100;
    saveSite();
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    irr = await fetchIrradiance(site.lat, site.lon);
    monthly ??= await loadMonthlyPsh(site.lat, site.lon);
    weather = await fetchWeatherNow(site.lat, site.lon) ?? weather;
    lastSync = DateTime.now();
    _p?.setInt('lastSync', lastSync!.millisecondsSinceEpoch);
    syncing = false;
    notifyListeners();
  }

  // ----- derived energy numbers -----
  List<double> loadHourly() {
    final out = List<double>.filled(24, 0);
    for (final a in appliances) {
      final kw = a.watts * a.qty / 1000;
      final hrs = a.hours.clamp(0, 24).toDouble();
      for (var k = 0; k < 24; k++) {
        final h = (a.start + k) % 24;
        final on = (hrs - k).clamp(0.0, 1.0).toDouble();
        out[h] += kw * on;
      }
    }
    return out;
  }

  double get dailyLoad => loadHourly().fold(0.0, (s, v) => s + v);

  ({double kw, int n}) activeNow([DateTime? at]) {
    final now = at ?? DateTime.now();
    var kw = 0.0;
    var n = 0;
    for (final a in appliances) {
      final off = (now.hour - a.start + 24) % 24;
      if (off < a.hours.clamp(0, 24).ceil()) {
        kw += a.watts * a.qty / 1000;
        n++;
      }
    }
    return (kw: kw, n: n);
  }

  // ----- tariffs & derived links between Settings, Profile and Home -----
  String get lang => prefs.lang;
  String t(String key) => tr(prefs.lang, key);
  StateTariff get st => book!.byId(prefs.stateId);
  Discom get discom => st.discoms.firstWhere((d) => d.id == prefs.discomId, orElse: () => st.discoms.first);
  CategoryTariff get tariffCat => st.cat(prefs.category);

  /// Monthly consumption used to pick the slab (appliance load x 30 days).
  double get monthlyUnits => dailyLoad * 30;

  /// Price of the next unit at the current consumption.
  double get unitPrice => book == null ? site.tariff : tariffCat.marginal(monthlyUnits);
  String get slabText => book == null ? '' : '${tariffCat.label} (${tariffCat.slabLabel(monthlyUnits)})';

  /// Daily kWh per kWp from the location's long-term sun hours.
  double get locationYield => (monthly?.annual ?? (fallbackPsh(site.lat).reduce((a, b) => a + b) / 12)) * pr;
  double get pr => (book == null ? 79.2 : st.pr) / 100;
  double? get exportRate => book == null ? null : st.exportRate;
  int get year0 => DateTime.now().year;

  void _syncDerived() {
    if (book != null) site.tariff = double.parse(unitPrice.toStringAsFixed(2));
  }

  void savePrefs() {
    _save('prefs', prefs.toJson());
    site.auto = prefs.autoSync;
    _syncDerived();
    saveSite();
  }

  void saveProfile() {
    _save('profile', profile.toJson());
    _syncDerived();
    saveSite();
  }

  /// Picks the state and its first DISCOM.
  void chooseState(String id) {
    prefs.stateId = id;
    prefs.discomId = st.discoms.first.id;
  }

  /// Day/night: the toggle wins; otherwise auto from the real sun position.
  bool isDark(DateTime now) {
    if (prefs.dark != null) return prefs.dark!;
    return solarPosition(now, site.lat, site.lon).alt <= 0; // auto: night when the sun is down
  }

  void setDark(bool v) {
    prefs.dark = v;
    savePrefs();
  }

  /// Moves the app to a new place: refetches sun data, picks the state when
  /// it is one of the supported ones, and updates the Home header.
  Future<void> setPlace(Place pl, {bool user = false}) async {
    place = pl;
    site.lat = pl.lat;
    site.lon = pl.lng;
    if (pl.city.isNotEmpty) site.city = pl.city;
    site.label = pl.subtitle;
    final detected = book?.detect(pl.region);
    if (detected != null && detected.id != prefs.stateId) {
      chooseState(detected.id);
      _save('prefs', prefs.toJson());
    }
    _syncDerived();
    saveSite();
    monthly = await loadMonthlyPsh(pl.lat, pl.lng);
    await sync();
  }

  Future<void> locate() async {
    final pl = await currentPlace();
    if (pl != null) await setPlace(pl);
  }

  void markCleaned() {
    lastCleaned = DateTime.now();
    _p?.setInt('lastCleaned', lastCleaned!.millisecondsSinceEpoch);
    notifyListeners();
  }

  int? get cleanDueInDays {
    final base = lastCleaned ?? profile.commissionDate;
    if (base == null) return null;
    return prefs.dustDays - DateTime.now().difference(base).inDays;
  }

  Future<void> resetAll() async {
    await _p?.clear();
    site = Site();
    brand = Brand();
    profile = Profile();
    prefs = Prefs();
    records = [];
    appliances = _defaultAppliances();
    appl = ApplCfg();
    rates = const Rates();
    applHistory = [];
    inverterCfg = InverterConfig();
    inverterSnap = null;
    uscHistory = [];
    inverterLogins = [];
    estimatePush = null;
    lastCleaned = null;
    services = [];
    weather = null;
    input = EstimateInput();
    customer = Customer();
    result = null;
    await _loadTariffs();
    _syncDerived();
    notifyListeners();
  }

  List<double> solarHourlyKw() {
    final g = irr?.hourly ?? List<double>.filled(24, 0);
    return g.map((v) => site.kwp * v / 1000 * pr).toList();
  }
}
