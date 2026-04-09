import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ================= CONFIG =================
const panelDark = Color(0xFF121821);
const accent = Color(0xFF00e5ff);
const textColor = Color(0xFFEAEAEA);
const bgColor = Color(0xFF0b0f14);

// ================= MODEL =================
class License {
  String id, nama, email;
  int maxDevice;
  bool isBlocked;

  License({
    required this.id,
    required this.nama,
    required this.email,
    required this.maxDevice,
    required this.isBlocked,
  });

  factory License.fromJson(Map<String, dynamic> j) {
    return License(
      id: j['id'],
      nama: j['nama'],
      email: j['email'],
      maxDevice: j['max_devices'],
      isBlocked: j['is_blocked'],
    );
  }
}

class Device {
  int id;
  String deviceId, versionId;
  DateTime? lastActive;
  bool isActive;

  Device({
    required this.id,
    required this.deviceId,
    required this.versionId,
    required this.lastActive,
    required this.isActive,
  });

  factory Device.fromJson(Map<String, dynamic> j) {
    return Device(
      id: j['id'],
      deviceId: j['device_id'] ?? "",
      versionId: j['version_id'] ?? "",
      lastActive: j['last_active'] != null
          ? DateTime.parse(j['last_active'])
          : null,
      isActive: j['is_active'] ?? false,
    );
  }
}

class AppConfig {
  String name;
  String baseUrl;
  String apiKey;

  AppConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      name: json['name'],
      baseUrl: json['baseUrl'],
      apiKey: json['apiKey'],
    );
  }
}

// ================= MAIN =================
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

// ================= PAGE =================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<License> licenses = [];
  List<Device> devices = [];
  String currentLicenseId = "";
  License? selected;

  // App Config
  List<AppConfig> appConfigs = [];
  AppConfig? currentAppConfig;
  int currentAppIndex = 0;

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    loadAppConfigs();
  }

  // ================= APP CONFIG =================
  Future<void> loadAppConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configString = prefs.getStringList('app_configs') ?? [];

    setState(() {
      appConfigs =
          configString.map((json) => AppConfig.fromJson(jsonDecode(json))).toList();

      if (appConfigs.isNotEmpty) {
        currentAppConfig = appConfigs[0];
        currentAppIndex = 0;
        loadLicenses();
      }
    });
  }

  Future<void> saveAppConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    appConfigs.add(config);

    final configString =
        appConfigs.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList('app_configs', configString);

    setState(() {
      currentAppConfig = config;
      currentAppIndex = appConfigs.length - 1;
    });

    loadLicenses();
  }

  void switchAppConfig(int index) {
    setState(() {
      currentAppIndex = index;
      currentAppConfig = appConfigs[index];
      selected = null;
      licenses.clear();
      devices.clear();
      currentLicenseId = "";
    });
    loadLicenses();
  }

  // ================= API =================
  Future<void> loadLicenses() async {
    if (currentAppConfig == null) return;

    setState(() => isLoading = true);

    try {
      final res = await http.get(
        Uri.parse("${currentAppConfig!.baseUrl}/rest/v1/licenses"),
        headers: {
          "apikey": currentAppConfig!.apiKey,
          "Authorization": "Bearer ${currentAppConfig!.apiKey}",
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          licenses = data.map((e) => License.fromJson(e)).toList();
          if (licenses.isNotEmpty && selected == null) {
            selected = licenses[0];
            currentLicenseId = licenses[0].id;
            loadDevices(licenses[0].id);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> loadDevices(String id) async {
    if (currentAppConfig == null) return;

    try {
      final res = await http.get(
        Uri.parse("${currentAppConfig!.baseUrl}/rest/v1/devices?license_id=eq.$id"),
        headers: {
          "apikey": currentAppConfig!.apiKey,
          "Authorization": "Bearer ${currentAppConfig!.apiKey}",
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          devices = data.map((e) => Device.fromJson(e)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error load devices: $e")),
        );
      }
    }
  }

  Future<void> toggle(Device d) async {
    if (currentAppConfig == null) return;

    try {
      bool newState = !d.isActive;

      await http.patch(
        Uri.parse("${currentAppConfig!.baseUrl}/rest/v1/devices?id=eq.${d.id}"),
        headers: {
          "apikey": currentAppConfig!.apiKey,
          "Authorization": "Bearer ${currentAppConfig!.apiKey}",
          "Content-Type": "application/json"
        },
        body: jsonEncode({"is_active": newState}),
      );

      await loadDevices(currentLicenseId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error toggle: $e")),
        );
      }
    }
  }

  bool isOnline(DateTime? last) {
    if (last == null) return false;
    return DateTime.now().difference(last).inMinutes <= 2;
  }

  // ================= UI BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ================= HEADER =================
            _buildHeader(),
            // ================= BODY =================
            Expanded(child: _buildBody()),
            // ================= FOOTER =================
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Text(
            "CONTROL SERVER",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const Spacer(),
          // Dropdown App Config
          Container(
            width: appConfigs.isEmpty ? 160 : 180,
            height: 36,
            decoration: BoxDecoration(
              color: panelDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: appConfigs.isEmpty
                ? const Center(
                    child: Text(
                      "No App",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: currentAppIndex,
                      isExpanded: true,
                      items: appConfigs.asMap().entries.map((entry) {
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              entry.value.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) switchAppConfig(value);
                      },
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Add App Button
          GestureDetector(
            onTap: () => _showAddAppDialog(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF16202b),
              ),
              child: const Icon(Icons.add, color: accent, size: 20),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        // ===== LEFT LIST =====
        Container(
          width: 140,
          color: panelDark,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : licenses.isEmpty
                  ? const Center(
                      child: Text(
                        "No licenses\n(Pilih App dulu)",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: licenses.length,
                      itemBuilder: (_, i) {
                        final l = licenses[i];
                        final isSelected = selected?.id == l.id;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              l.email,
                              style: TextStyle(
                                color: isSelected ? accent : Colors.white,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                selected = l;
                                currentLicenseId = l.id;
                              });
                              loadDevices(l.id);
                            },
                          ),
                        );
                      },
                    ),
        ),
        // ===== RIGHT PANEL =====
        Expanded(child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildRightPanel() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // ===== TABLE =====
          panel(
            Column(
              children: [
                tableHeader(),
                ...List.generate(5, (i) => rowDevice(i)),
              ],
            ),
          ),
          // ===== ACTION BUTTONS =====
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionBtn("➕ Tambah Akses"),
              _actionBtn("🗑 Hapus Akses"),
            ],
          ),
          // ===== DETAIL =====
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "DETAIL USER",
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                _detailRow("Nama", selected?.nama ?? "-"),
                _detailRow("Email", selected?.email ?? "-"),
                _detailRow("Lisensi", selected?.id ?? "-"),
                _detailRow("Max Device", "${selected?.maxDevice ?? "-"}"),
                _detailRow(
                  "Status",
                  selected == null
                      ? "-"
                      : (selected!.isBlocked ? "DIBLOKIR" : "AKTIF"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: panel(
              const Text(
                "Status: siap...",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _footerBtn("Update Aplikasi", onTap: _showUpdateDialog),
        ],
      ),
    );
  }

  // ================= DIALOGS =================
  void _showAddAppDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController(
        text: "https://your-project.supabase.co");
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        title: const Row(
          children: [
            Icon(Icons.add_business, color: accent),
            SizedBox(width: 8),
            Text("Tambah Aplikasi", style: TextStyle(color: accent)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Nama Aplikasi",
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Base URL",
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "API Key",
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Gunakan anon/public key dari Supabase",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accent),
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  urlController.text.isNotEmpty &&
                  keyController.text.isNotEmpty) {
                saveAppConfig(AppConfig(
                  name: nameController.text,
                  baseUrl: urlController.text,
                  apiKey: keyController.text,
                ));
                Navigator.pop(context);
              }
            },
            child: const Text(
              "TAMBAH",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog() {
  final versionController = TextEditingController();
  final descController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  showDialog(
    context: context,
    builder: (BuildContext context) => AlertDialog(  // Fixed: Added proper parameter name
      backgroundColor: bgColor,
      title: const Row(
        children: [
          Icon(Icons.system_update, color: accent),
          SizedBox(width: 8),
          Text("Update Versi", style: TextStyle(color: accent)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: versionController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Version *",
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  selectedDate = date;
                  setState(() {});
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Tanggal Rilis *", style: TextStyle(color: Colors.white)),
                    Text(
                      "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                      style: const TextStyle(color: accent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Deskripsi",
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [  // Fixed: Proper actions array structure
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Batal", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: accent),
          onPressed: () async {
            if (versionController.text.isNotEmpty) {
              if (currentAppConfig != null) {
                final url = "${currentAppConfig!.baseUrl}/rest/v1/app_versions";
                
                try {
                  final res = await http.post(
                    Uri.parse(url),
                    headers: {
                      "apikey": currentAppConfig!.apiKey,
                      "Authorization": "Bearer ${currentAppConfig!.apiKey}",
                      "Content-Type": "application/json",
                    },
                    body: jsonEncode({
                      "version": versionController.text.trim(),
                      "release_date": "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                      "description": descController.text.trim(),
                      "is_mandatory": false,
                    }),
                  );

                  if (res.statusCode == 201) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ Update berhasil disimpan!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("❌ Error: ${res.statusCode}"),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("❌ Error: $e")),
                  );
                }
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("❌ Version tidak boleh kosong!")),
              );
            }
          },
          child: const Text(
            "SIMPAN",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ],  // Fixed: Proper closing
    ),
  );
}

  // ================= COMPONENTS =================
  Widget panel(Widget child) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1f2a36)),
      ),
      child: child,
    );
  }

  Widget tableHeader() {
    return const Row(
      children: [
        SizedBox(width: 60),
        Expanded(child: Text("PC ID", style: TextStyle(color: accent, fontWeight: FontWeight.bold))),
        SizedBox(width: 80, child: Text("VERSI", style: TextStyle(color: accent, fontWeight: FontWeight.bold))),
        SizedBox(width: 90, child: Text("STATUS", style: TextStyle(color: accent, fontWeight: FontWeight.bold))),
        SizedBox(width: 100, child: Text("AKSI", style: TextStyle(color: accent, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget rowDevice(int i) {
    Device? d = i < devices.length ? devices[i] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text("PC ${i + 1}", style: const TextStyle(color: Colors.white))),
          Expanded(child: _input(d?.deviceId ?? "")),
          SizedBox(width: 80, child: _input(d?.versionId ?? "")),
          SizedBox(
            width: 90,
            child: Text(
              d == null
                  ? "-"
                  : (isOnline(d.lastActive) ? "● Online" : "● Offline"),
              style: TextStyle(
                color: d == null
                    ? Colors.grey
                    : (isOnline(d.lastActive) ? Colors.greenAccent : Colors.redAccent),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: InkWell(
              onTap: d == null ? null : () => toggle(d!),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: d?.isActive == true ? Colors.green : Colors.red,
                    width: 2,
                  ),
                  color: (d?.isActive == true ? Colors.green : Colors.red).withOpacity(0.1),
                ),
                child: Text(
                  d == null
                      ? "-"
                      : d.isActive
                          ? "Aktif"
                          : "Blokir",
                  style: TextStyle(
                    color: d?.isActive == true ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(String v) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16202b),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          v.isEmpty ? "-" : v,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _actionBtn(String text) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$text - Coming Soon")),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: accent),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFF16202b),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _footerBtn(String text, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: accent, width: 2),
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF16202b),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: accent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            "$label: ",
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: value.contains("DIBLOKIR") 
                  ? Colors.redAccent 
                  : textColor,  // Fixed: Combined color logic, removed duplicate
              fontWeight: value.contains("DIBLOKIR") ? FontWeight.bold : null,
            ),
          ),
        ),
      ],
    ),
  );
}
}