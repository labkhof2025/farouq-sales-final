
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FarouqApp());

const gold = Color(0xfff4c767);
const bg = Color(0xff050505);

class FarouqApp extends StatelessWidget {
  const FarouqApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'حلواني الفاروق',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: LoginPage()),
  );
}

class DB {
  static const key = 'farouq_db_v1';
  static Future<Map<String, dynamic>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw != null) return jsonDecode(raw);
    final data = {
      'branches': ['الحصايا', 'حسين', 'عثمان', 'المصنع'],
      'products': ['الباسطة', 'البسكويت', 'اليانسون', 'الشريق'],
      'sales': [],
      'expenses': [],
      'stock': {'الباسطة': 0.0, 'البسكويت': 0.0, 'اليانسون': 0.0, 'الشريق': 0.0}
    };
    await save(data);
    return data;
  }
  static Future<void> save(Map<String, dynamic> d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(d));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final u = TextEditingController(text: 'admin');
  final p = TextEditingController(text: '1234');
  void login() {
    final ok = (u.text == 'admin' && p.text == '1234') || (u.text == 'seller' && p.text == '1111');
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بيانات الدخول غير صحيحة')));
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Home(user: u.text, role: u.text == 'admin' ? 'مدير' : 'موظف'),
    )));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: card(Column(children: [
        logo(),
        const Text('حلواني الفاروق', style: TextStyle(fontSize: 32, color: gold, fontWeight: FontWeight.bold)),
        const Text('نظام إدارة المبيعات'),
        const SizedBox(height: 16),
        input('اسم المستخدم', u),
        input('كلمة المرور', p, pass: true),
        btn('دخول', login),
        const SizedBox(height: 10),
        const Text('admin / 1234  |  seller / 1111', style: TextStyle(color: Colors.white54)),
      ])),
    )),
  );
}

class Home extends StatefulWidget {
  final String user, role;
  const Home({super.key, required this.user, required this.role});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  Map<String, dynamic> db = {};
  int tab = 0;
  String branch = 'الحصايا', product = 'الباسطة', pay = 'كاش', period = 'day';
  final qty = TextEditingController();
  final price = TextEditingController();
  final cust = TextEditingController();
  final stQty = TextEditingController();
  final exTitle = TextEditingController();
  final exAmt = TextEditingController();

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { db = await DB.load(); setState(() {}); }
  List get sales => db['sales'] ?? [];
  List get expenses => db['expenses'] ?? [];
  String money(num n) => NumberFormat.decimalPattern('ar').format(n);
  double sum(Iterable xs, [String k = 'total']) => xs.fold(0.0, (a, b) => a + ((b[k] ?? 0) as num).toDouble());

  bool inPeriod(Map s) {
    final d = DateTime.parse(s['date']);
    final n = DateTime.now();
    if (period == 'day') return DateFormat('yyyy-MM-dd').format(d) == DateFormat('yyyy-MM-dd').format(n);
    if (period == 'week') return n.difference(d).inDays < 7;
    if (period == 'month') return d.year == n.year && d.month == n.month;
    return d.year == n.year;
  }

  String top(Iterable xs, String key) {
    final m = <String, double>{};
    for (final s in xs) { m[s[key]] = (m[s[key]] ?? 0) + ((s['total'] ?? 0) as num).toDouble(); }
    if (m.isEmpty) return '-';
    final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return '${l.first.key} — ${money(l.first.value)}';
  }

  Future<void> saveSale() async {
    final q = double.tryParse(qty.text) ?? 0;
    final pr = double.tryParse(price.text) ?? 0;
    if (q <= 0 || pr <= 0) { msg('أدخل الكمية والسعر'); return; }
    db['sales'].add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'invoice': 'F${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      'date': DateTime.now().toIso8601String(),
      'branch': branch, 'product': product, 'qty': q, 'price': pr,
      'total': q * pr, 'payment': pay, 'customer': cust.text, 'seller': widget.user
    });
    db['stock'][product] = ((db['stock'][product] ?? 0) as num).toDouble() - q;
    await DB.save(db);
    qty.clear(); price.clear(); cust.clear();
    setState(() => tab = 0);
    msg('تم حفظ البيع');
  }

  Future<void> addStock() async {
    final q = double.tryParse(stQty.text) ?? 0;
    if (q <= 0) { msg('أدخل الكمية'); return; }
    db['stock'][product] = ((db['stock'][product] ?? 0) as num).toDouble() + q;
    await DB.save(db); stQty.clear(); setState(() {});
  }

  Future<void> addExpense() async {
    final a = double.tryParse(exAmt.text) ?? 0;
    if (exTitle.text.isEmpty || a <= 0) { msg('أدخل البيان والمبلغ'); return; }
    db['expenses'].add({'id': DateTime.now().millisecondsSinceEpoch, 'date': DateTime.now().toIso8601String(), 'title': exTitle.text, 'amount': a});
    await DB.save(db); exTitle.clear(); exAmt.clear(); setState(() {});
  }

  Future<void> exportCsv() async {
    final rows = [
      ['invoice', 'date', 'branch', 'product', 'qty', 'price', 'total', 'payment', 'seller'],
      ...sales.where((s) => inPeriod(Map.from(s))).map((s) => [s['invoice'], s['date'], s['branch'], s['product'], s['qty'], s['price'], s['total'], s['payment'], s['seller']])
    ];
    final f = File('${(await getTemporaryDirectory()).path}/farouq_report.csv');
    await f.writeAsString(const ListToCsvConverter().convert(rows));
    await Share.shareXFiles([XFile(f.path)], text: 'تقرير حلواني الفاروق');
  }

  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext c) {
    if (db.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final today = sales.where((s) => DateFormat('yyyy-MM-dd').format(DateTime.parse(s['date'])) == DateFormat('yyyy-MM-dd').format(DateTime.now())).toList();
    final filtered = sales.where((s) => inPeriod(Map.from(s))).toList();
    final ex = expenses.where((e) => inPeriod(Map.from(e))).toList();
    return Scaffold(
      appBar: AppBar(title: Text('حلواني الفاروق - ${widget.role}'), backgroundColor: Colors.black),
      body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: [dash(today), salePage(), stockPage(), reports(filtered), finance(filtered, ex)][tab]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab, onTap: (i) => setState(() => tab = i),
        type: BottomNavigationBarType.fixed, selectedItemColor: gold, backgroundColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'بيع'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'مخزن'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'تقارير'),
          BottomNavigationBarItem(icon: Icon(Icons.money), label: 'مالية'),
        ],
      ),
    );
  }

  Widget dash(List today) => Column(children: [
    logo(),
    const Text('لوحة التحكم', style: TextStyle(fontSize: 26, color: gold, fontWeight: FontWeight.bold)),
    GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.25, children: [
      stat('إجمالي اليوم', money(sum(today)), 'ج.م'),
      stat('الكاش', money(sum(today.where((x) => x['payment'] == 'كاش'))), 'ج.م'),
      stat('بنكك', money(sum(today.where((x) => x['payment'] == 'بنكك'))), 'ج.م'),
      stat('الفواتير', '${today.length}', 'فاتورة'),
    ]),
    card(Text('أكثر معرض: ${top(today, 'branch')}', style: const TextStyle(color: gold, fontSize: 20))),
    card(Text('أكثر منتج: ${top(today, 'product')}', style: const TextStyle(color: gold, fontSize: 20))),
  ]);

  Widget salePage() => card(Column(children: [
    const Text('إضافة بيع', style: TextStyle(fontSize: 24, color: gold, fontWeight: FontWeight.bold)),
    drop('المعرض', branch, List<String>.from(db['branches']), (v) => setState(() => branch = v!)),
    drop('المنتج', product, List<String>.from(db['products']), (v) => setState(() => product = v!)),
    input('الكمية بالكيلو', qty, num: true),
    input('سعر الكيلو', price, num: true),
    drop('طريقة الدفع', pay, ['كاش', 'بنكك'], (v) => setState(() => pay = v!)),
    input('اسم العميل اختياري', cust),
    btn('حفظ البيع', saveSale),
  ]));

  Widget stockPage() => Column(children: [
    card(Column(children: [
      const Text('المخزن', style: TextStyle(fontSize: 24, color: gold, fontWeight: FontWeight.bold)),
      drop('المنتج', product, List<String>.from(db['products']), (v) => setState(() => product = v!)),
      input('إضافة كمية بالكيلو', stQty, num: true),
      btn('إضافة للمخزن', addStock),
    ])),
    ...List<String>.from(db['products']).map((p) => card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(p, style: const TextStyle(color: gold, fontSize: 18)),
      Text('${money(db['stock'][p] ?? 0)} كجم'),
    ])))
  ]);

  Widget reports(List filtered) => Column(children: [
    card(Column(children: [
      const Text('التقارير', style: TextStyle(fontSize: 24, color: gold, fontWeight: FontWeight.bold)),
      drop('الفترة', period, ['day', 'week', 'month', 'year'], (v) => setState(() => period = v!)),
      Text('الإجمالي: ${money(sum(filtered))} ج.م'),
      Text('الفواتير: ${filtered.length}'),
      btn('تصدير Excel/CSV', exportCsv),
    ])),
    ...filtered.reversed.map((s) => card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${s['invoice']} - ${s['branch']}', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
      Text('${s['product']} | ${s['qty']} كجم | ${money(s['total'])} ج.م | ${s['payment']}'),
      Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(s['date'])), style: const TextStyle(color: Colors.white54)),
    ])))
  ]);

  Widget finance(List filtered, List ex) {
    final exSum = ex.fold(0.0, (a, e) => a + ((e['amount'] ?? 0) as num).toDouble());
    return Column(children: [
      card(Column(children: [
        const Text('المصروفات', style: TextStyle(fontSize: 24, color: gold, fontWeight: FontWeight.bold)),
        input('بيان المصروف', exTitle),
        input('المبلغ', exAmt, num: true),
        btn('إضافة مصروف', addExpense),
      ])),
      stat('إجمالي المبيعات', money(sum(filtered)), 'ج.م'),
      stat('المصروفات', money(exSum), 'ج.م'),
      stat('الصافي', money(sum(filtered) - exSum), 'ج.م'),
      ...ex.reversed.map((e) => card(Text('${e['title']} — ${money(e['amount'])} ج.م'))),
    ]);
  }

  Widget stat(String t, String v, String u) => card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(t, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    Text(u, style: const TextStyle(color: Colors.white54)),
  ]));

  Widget drop(String l, String val, List<String> vals, Function(String?) ch) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(l, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
    DropdownButtonFormField(
      value: val, items: vals.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: ch,
      decoration: InputDecoration(filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
    ),
    const SizedBox(height: 10)
  ]);
}

Widget logo() => Container(
  width: 88, height: 88, alignment: Alignment.center,
  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold, width: 5), color: Colors.black),
  child: const Text('F', style: TextStyle(fontSize: 50, color: gold, fontWeight: FontWeight.bold)),
);

Widget card(Widget child) => Container(
  width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(color: const Color(0xdd111111), border: Border.all(color: const Color(0xff9d7326)), borderRadius: BorderRadius.circular(22)),
  child: child,
);

Widget input(String l, TextEditingController c, {bool pass = false, bool num = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text(l, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
  TextField(
    controller: c, obscureText: pass, keyboardType: num ? TextInputType.number : null,
    decoration: InputDecoration(filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
  ),
  const SizedBox(height: 10)
]);

Widget btn(String t, VoidCallback f) => SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: f,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xff1b1b1b), foregroundColor: gold, padding: const EdgeInsets.all(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xff9d7326))),
    ),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
  ),
);
