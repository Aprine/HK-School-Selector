import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/school.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.school, this.imageAssetPath});

  final School school;
  final String? imageAssetPath;

  Uri _mapsUri() {
    if (school.latitude != null && school.longitude != null) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${school.latitude},${school.longitude}',
      );
    }

    final query = school.address.isNotEmpty ? school.address : school.schoolName;
    return Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': query,
    });
  }

  Uri? _websiteUri() {
    final website = school.website.trim();
    if (website.isEmpty) return null;

    final withScheme = website.startsWith('http://') || website.startsWith('https://')
        ? website
        : 'https://$website';
    return Uri.tryParse(withScheme);
  }

  Uri? _phoneUri() {
    final normalized = school.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return null;
    return Uri.parse('tel:$normalized');
  }

  Future<void> _launchUri(BuildContext context, Uri uri, String errorMessage) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final websiteUri = _websiteUri();
    final phoneUri = _phoneUri();

    return Scaffold(
      appBar: AppBar(title: const Text('School Details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF0F766E), Color(0xFF134E4A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Text(
                school.schoolName.isEmpty ? 'Unknown School' : school.schoolName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageAssetPath == null || imageAssetPath!.isEmpty
                  ? _imagePlaceholder(height: 190)
                  : Image.asset(
                      imageAssetPath!,
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(height: 190),
                    ),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              icon: Icons.school_outlined,
              label: 'Type',
              value: school.type,
            ),
            _DetailCard(
              icon: Icons.map_outlined,
              label: 'District',
              value: school.district,
            ),
            _DetailCard(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: school.address,
            ),
            _DetailCard(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: school.phone,
              trailing: phoneUri == null
                  ? null
                  : IconButton(
                      tooltip: 'Call',
                      onPressed: () => _launchUri(
                        context,
                        phoneUri,
                        'Unable to open dialer.',
                      ),
                      icon: const Icon(Icons.call_outlined),
                    ),
            ),
            _DetailCard(
              icon: Icons.language_outlined,
              label: 'Website',
              value: school.website,
              trailing: websiteUri == null
                  ? null
                  : IconButton(
                      tooltip: 'Open website',
                      onPressed: () => _launchUri(
                        context,
                        websiteUri,
                        'Unable to open website.',
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _launchUri(
                  context,
                  _mapsUri(),
                  'Unable to open Google Maps.',
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Google Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder({required double height}) {
    return Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFFE5EEEC),
      child: const Center(
        child: Icon(
          Icons.photo_camera_back_outlined,
          color: Color(0xFF6B7280),
          size: 36,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? 'N/A' : value.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: const Color(0xFF0F766E)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
