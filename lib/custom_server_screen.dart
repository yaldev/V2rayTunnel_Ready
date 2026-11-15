import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'database_helper.dart';
import 'config_generator.dart';

class CustomServerScreen extends StatefulWidget {
  const CustomServerScreen({super.key});

  @override
  State<CustomServerScreen> createState() => _CustomServerScreenState();
}

class _CustomServerScreenState extends State<CustomServerScreen> {
  final TextEditingController _hostController = TextEditingController();
  String _selectedProtocol = 'VLESS';
  final List<String> _protocols = ['VLESS', 'Trojan', 'VMess'];
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    UnityAds.load(
      placementId: 'BP_Rewarded_Android',
      onComplete: (placementId) {
        if (!mounted) return;
        setState(() {
          _isAdLoaded = true;
        });
      },
      onFailed: (placementId, error, message) {
        if (!mounted) return;
        setState(() {
          _isAdLoaded = false;
        });
      },
    );
  }

  void _onGeneratePressed() {
    String host = _hostController.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a Host / SNI")),
      );
      return;
    }

    if (!_isAdLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ad not ready, please wait.")),
      );
      _loadRewardedAd();
      return;
    }

    UnityAds.show(
      placementId: 'BP_Rewarded_Android',
      onComplete: (placementId) {
        if (!mounted) return;
        setState(() {
          _isAdLoaded = false;
        });
        _generateConfig(host);
        _loadRewardedAd();
      },
      onFailed: (placementId, error, message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ad failed to show: $message")),
        );
        _loadRewardedAd();
      },
      onSkipped: (placementId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ad was skipped. You must watch the ad to generate config.")),
        );
        _loadRewardedAd();
      },
    );
  }

  Future<void> _generateConfig(String host) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00BFFF),
        ),
      ),
    );

    try {
      final fastestKey = await DatabaseHelper().getFastestKey();
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (fastestKey == null || fastestKey['ip'] == null || (fastestKey['ip'] as String).isEmpty) {
        _showErrorDialog("No connection keys available from GitHub. Please check internet connection.");
        return;
      }

      String uuidOrPass = fastestKey['uuid_or_pass'] ?? '';
      String path = fastestKey['path'] ?? '/';
      String ipAddress = fastestKey['ip'] ?? '';
      int port = fastestKey['port'] ?? 443;
      String security = fastestKey['security'] ?? 'tls';
      String type = fastestKey['type'] ?? 'ws';
      String name = "Custom Host ($_selectedProtocol)";

      String uri = '';
      if (_selectedProtocol == 'VLESS') {
        uri = ConfigGenerator.generateVless(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: host, name: name, security: security, type: type);
      } else if (_selectedProtocol == 'Trojan') {
        uri = ConfigGenerator.generateTrojan(password: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: host, name: name, security: security, type: type);
      } else if (_selectedProtocol == 'VMess') {
        uri = ConfigGenerator.generateVmess(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: host, name: name, security: security, type: type);
      }

      if (!mounted) return;
      _showConfigDialog(uri);
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading
      }
      _showErrorDialog("Error generating config: $e");
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showConfigDialog(String uri) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Generated $_selectedProtocol Config"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Config generated successfully after watching ad!",
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(
                uri,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00BFFF),
        title: const Text(
          "Custom Host (Watch Ad)",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Enter your custom Host / SNI and select a protocol to generate a high-speed VPN configuration.",
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _hostController,
              decoration: InputDecoration(
                labelText: "Host / SNI",
                hintText: "e.g., b.i.instagram.com",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00BFFF), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedProtocol,
              decoration: InputDecoration(
                labelText: "Protocol",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00BFFF), width: 2),
                ),
              ),
              items: _protocols.map((protocol) {
                return DropdownMenuItem(
                  value: protocol,
                  child: Text(protocol),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedProtocol = value;
                  });
                }
              },
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
              icon: const Icon(Icons.video_call, size: 24),
              label: Text(
                _isAdLoaded ? "Generate Config (Watch Ad)" : "Loading Ad...",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: _onGeneratePressed,
            ),
          ],
        ),
      ),
    );
  }
}
