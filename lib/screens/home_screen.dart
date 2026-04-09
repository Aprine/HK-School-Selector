import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/school.dart';
import '../services/api_service.dart';
import '../services/ai_assistant_service.dart';
import '../services/auth_service.dart';
import '../services/qwen_chat_service.dart';
import '../services/school_image_service.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.currentUser,
    required this.authService,
    this.enableLocation = true,
    ApiService? apiService,
  }) : _apiService = apiService;

  final ApiService? _apiService;
  final String currentUser;
  final AuthService authService;
  final bool enableLocation;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _allDistricts = 'All Districts';
  static const String _allTypes = 'All Types';

  static const Map<String, String> _typeFilters = <String, String>{
    _allTypes: _allTypes,
    'Primary': 'primary',
    'Secondary': 'secondary',
    'Government': 'government',
    'Aided': 'aid',
    'PLK': 'plk',
  };

  late final ApiService _apiService;
  final AiAssistantService _aiAssistantService = AiAssistantService();
  final QwenChatService _qwenChatService = QwenChatService();
  final SchoolImageService _schoolImageService = SchoolImageService();
  late Future<List<School>> _schoolsFuture;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String _searchQuery = '';
  String _selectedDistrict = _allDistricts;
  String _selectedType = _allTypes;
  bool _showFavoritesOnly = false;
  _SortOption _sortOption = _SortOption.nameAsc;

  Set<String> _favoriteSchoolIds = <String>{};
  Map<String, String> _schoolImageMap = const <String, String>{};

  Position? _currentPosition;
  bool _isLocating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _apiService = widget._apiService ?? ApiService();
    _schoolsFuture = _apiService.fetchSchools();
    _loadFavorites();
    _loadSchoolImageMap();
    if (widget.enableLocation) {
      _loadCurrentLocation();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _favoritesKey =>
      widget.authService.favoritesKeyForUser(widget.currentUser);

  Future<void> _refreshSchools() async {
    setState(() {
      _schoolsFuture = _apiService.fetchSchools();
    });
    try {
      await _schoolsFuture;
    } catch (_) {}
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_favoritesKey) ?? const <String>[];

    if (!mounted) return;
    setState(() {
      _favoriteSchoolIds = saved.toSet();
    });
  }

  Future<void> _loadSchoolImageMap() async {
    final imageMap = await _schoolImageService.loadImageMap();
    if (!mounted) return;
    setState(() {
      _schoolImageMap = imageMap;
    });
  }

  Future<void> _toggleFavorite(School school) async {
    final schoolId = school.id;
    final previous = Set<String>.from(_favoriteSchoolIds);
    final next = Set<String>.from(_favoriteSchoolIds);

    if (next.contains(schoolId)) {
      next.remove(schoolId);
    } else {
      next.add(schoolId);
    }

    setState(() {
      _favoriteSchoolIds = next;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favoriteSchoolIds.toList());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteSchoolIds = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save favorite. Please retry.')),
      );
    }
  }

  Future<void> _logout() async {
    await widget.authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
      (route) => false,
    );
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _isLocating = false;
          _locationError = 'Location service is disabled.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _isLocating = false;
          _locationError = 'Location permission was denied.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLocating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _locationError = 'Unable to get current location.';
      });
    }
  }

  Future<void> _openAiAssistant(List<School> schools) async {
    final inputController = TextEditingController();
    final messages = <ChatTurn>[
      const ChatTurn(
        role: 'assistant',
        content:
            'Hi! Ask me to refine filters. Example: \"nearby primary schools in Tai Po\".',
      ),
    ];
    var isSending = false;

    String buildContextPrompt() {
      final district = _selectedDistrict;
      final type = _selectedType;
      final fav = _showFavoritesOnly ? 'favorites only' : 'all schools';
      final locationPart = _currentPosition == null
          ? 'Current location: unavailable.'
          : 'Current location: lat=${_currentPosition!.latitude.toStringAsFixed(6)}, lng=${_currentPosition!.longitude.toStringAsFixed(6)}.';
      final nearby = _recommendedNearbySchools(schools);
      final nearbyPart = nearby.isEmpty
          ? 'Nearby school samples: none.'
          : 'Nearby school samples: ${nearby.map((e) => '${e.school.schoolName}(${e.distanceKm.toStringAsFixed(1)}km)').join(', ')}.';
      return 'Current filter context: district=$district, type=$type, scope=$fav. '
          '$locationPart $nearbyPart '
          'Only use schools from this app dataset. If uncertain, ask user to clarify the school name.';
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> send() async {
              final text = inputController.text.trim();
              if (text.isEmpty || isSending) return;

              setModalState(() {
                isSending = true;
                messages.add(ChatTurn(role: 'user', content: text));
              });
              inputController.clear();

              try {
                final localDistance = _tryBuildLocalDistanceAnswer(text, schools);
                if (localDistance != null) {
                  setModalState(() {
                    messages.add(ChatTurn(role: 'assistant', content: localDistance));
                    isSending = false;
                  });
                  return;
                }

                final localSchoolInfo = _tryBuildLocalSchoolInfoAnswer(text, schools);
                if (localSchoolInfo != null) {
                  setModalState(() {
                    messages.add(ChatTurn(role: 'assistant', content: localSchoolInfo));
                    isSending = false;
                  });
                  return;
                }

                String replyText;
                void applySuggestion(AiSuggestion suggestion) {
                  if (!mounted) return;
                  setState(() {
                    if (suggestion.district != null &&
                        _districtOptions(schools).contains(suggestion.district)) {
                      _selectedDistrict = suggestion.district!;
                    }
                    if (suggestion.type != null &&
                        _typeFilters.keys.contains(suggestion.type)) {
                      _selectedType = suggestion.type!;
                    }
                    if (suggestion.favoritesOnly != null) {
                      _showFavoritesOnly = suggestion.favoritesOnly!;
                    }
                    if (suggestion.sort == 'distance') {
                      _sortOption = _SortOption.distanceAsc;
                    } else if (suggestion.sort == 'distance_desc') {
                      _sortOption = _SortOption.distanceDesc;
                    }
                    if (suggestion.searchQuery != null &&
                        suggestion.searchQuery!.trim().isNotEmpty) {
                      _searchQuery = suggestion.searchQuery!.trim();
                      _searchController.text = _searchQuery;
                    }
                  });
                }

                if (_qwenChatService.isConfigured) {
                  replyText = await _qwenChatService.reply(
                    history: messages,
                    userMessage: text,
                    appContext: buildContextPrompt(),
                  );
                  final localSuggestion = await _aiAssistantService.suggest(
                    query: text,
                    districts: _districtOptions(schools),
                    supportedTypes: _typeFilters.keys.toList(growable: false),
                  );
                  applySuggestion(localSuggestion);
                } else {
                  final suggestion = await _aiAssistantService.suggest(
                    query: text,
                    districts: _districtOptions(schools),
                    supportedTypes: _typeFilters.keys.toList(growable: false),
                  );
                  replyText = suggestion.message;
                  applySuggestion(suggestion);
                }

                setModalState(() {
                  messages.add(ChatTurn(role: 'assistant', content: replyText));
                });
              } catch (e) {
                setModalState(() {
                  messages.add(
                    ChatTurn(role: 'assistant', content: 'AI error: $e'),
                  );
                });
              } finally {
                setModalState(() {
                  isSending = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: SizedBox(
                height: 520,
                child: Column(
                  children: [
                    const Text(
                      'AI Chat (Token Saver)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isUser = msg.role == 'user';
                          return Align(
                            alignment:
                                isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              constraints: const BoxConstraints(maxWidth: 320),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFFEFF4F3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                msg.content,
                                style: TextStyle(
                                  color: isUser ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: inputController,
                            minLines: 1,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: _qwenChatService.isConfigured
                                  ? 'Ask about school choices...'
                                  : 'Ask to auto-apply filters...',
                            ),
                            onSubmitted: (_) => send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: isSending ? null : send,
                          icon: Icon(
                            isSending ? Icons.hourglass_top_rounded : Icons.send_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String? _tryBuildLocalDistanceAnswer(String userText, List<School> schools) {
    final q = userText.toLowerCase();
    final asksDistance = q.contains('how far') ||
        q.contains('distance') ||
        q.contains('far from') ||
        q.contains('多远') ||
        q.contains('距离');
    final asksNearest = q.contains('最近') ||
        q.contains('nearest') ||
        q.contains('closest');
    final asksFarthest = q.contains('最远') ||
        q.contains('farthest') ||
        q.contains('furthest');

    if (!asksDistance && !asksNearest && !asksFarthest) return null;
    if (_currentPosition == null) {
      return '我还拿不到你的定位，无法计算距离。请先允许定位权限，然后点右上角 Refresh 再试。';
    }

    final withLocation = schools
        .where((s) => s.latitude != null && s.longitude != null)
        .toList(growable: false);
    if (withLocation.isEmpty) return null;

    if (asksNearest || asksFarthest) {
      School? best;
      var bestMeters = asksNearest ? double.infinity : -1.0;
      for (final school in withLocation) {
        final meters = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          school.latitude!,
          school.longitude!,
        );
        if (asksNearest) {
          if (meters < bestMeters) {
            bestMeters = meters;
            best = school;
          }
        } else {
          if (meters > bestMeters) {
            bestMeters = meters;
            best = school;
          }
        }
      }

      if (best != null) {
        final km = (bestMeters / 1000);
        final label = asksNearest ? '最近学校' : '最远学校';
        return '$label: ${best.schoolName}（约 ${km.toStringAsFixed(1)} km）';
      }
    }

    final matched = _findBestMatchingSchool(q, withLocation);

    if (matched == null) return null;

    final meters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      matched.latitude!,
      matched.longitude!,
    );
    final km = meters / 1000;
    return '${matched.schoolName} 距离你约 ${km.toStringAsFixed(1)} km。';
  }

  String? _tryBuildLocalSchoolInfoAnswer(String userText, List<School> schools) {
    final q = userText.toLowerCase();
    final asksSchoolInfo = q.contains('学校') ||
        q.contains('school') ||
        q.contains('地址') ||
        q.contains('address') ||
        q.contains('电话') ||
        q.contains('phone') ||
        q.contains('网站') ||
        q.contains('website') ||
        q.contains('网址') ||
        q.contains('district') ||
        q.contains('地区') ||
        q.contains('type') ||
        q.contains('类型');
    if (!asksSchoolInfo) return null;

    final matched = _findBestMatchingSchool(q, schools);
    if (matched == null) return null;

    final address = matched.address.isEmpty ? '-' : matched.address;
    final phone = matched.phone.isEmpty ? '-' : matched.phone;
    final website = matched.website.isEmpty ? '-' : matched.website;
    final type = matched.type.isEmpty ? '-' : matched.type;
    final district = matched.district.isEmpty ? '-' : matched.district;

    return '基于项目数据：\n'
        '学校：${matched.schoolName}\n'
        '类型：$type\n'
        '地区：$district\n'
        '地址：$address\n'
        '电话：$phone\n'
        '网站：$website';
  }

  School? _findBestMatchingSchool(String queryLower, List<School> schools) {
    final normalizedQuery = _normalizeForSearch(queryLower);
    final queryTokens = _tokenizeForSearch(queryLower);

    School? matched;
    var matchedScore = 0.0;

    for (final school in schools) {
      final name = school.schoolName.toLowerCase();
      final normalizedName = _normalizeForSearch(name);

      var score = 0.0;
      if (queryLower.contains(name) || name.contains(queryLower)) {
        score = 120;
      } else if (normalizedQuery.contains(normalizedName) ||
          normalizedName.contains(normalizedQuery)) {
        score = 95;
      } else {
        for (final token in queryTokens) {
          if (normalizedName.contains(token)) {
            score += 18;
          }
        }
        score += _bigramSimilarity(normalizedName, normalizedQuery) * 40;
      }

      if (score > matchedScore) {
        matched = school;
        matchedScore = score;
      }
    }

    if (matchedScore < 18) return null;
    return matched;
  }

  List<School> _applyFilters(List<School> schools) {
    final filtered = schools.where((school) {
      final query = _searchQuery.trim().toLowerCase();
      final schoolName = school.schoolName.toLowerCase();

      final matchesName = query.isEmpty || _matchesSchoolNameFuzzy(schoolName, query);
      final matchesDistrict =
          _selectedDistrict == _allDistricts || school.district == _selectedDistrict;
      final matchesType = _matchesTypeFilter(school);
      final matchesFavorite =
          !_showFavoritesOnly || _favoriteSchoolIds.contains(school.id);

      return matchesName && matchesDistrict && matchesType && matchesFavorite;
    }).toList(growable: false);

    return _sortSchools(filtered);
  }

  bool _matchesSchoolNameFuzzy(String schoolNameLower, String queryLower) {
    if (schoolNameLower.contains(queryLower)) return true;

    final normalizedName = _normalizeForSearch(schoolNameLower);
    final normalizedQuery = _normalizeForSearch(queryLower);
    if (normalizedQuery.isEmpty) return true;
    if (normalizedName.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedName)) {
      return true;
    }

    final tokens = _tokenizeForSearch(queryLower);
    if (tokens.isNotEmpty) {
      final matchedTokenCount =
          tokens.where((token) => normalizedName.contains(token)).length;
      if (matchedTokenCount >= 1) return true;
    }

    return _bigramSimilarity(normalizedName, normalizedQuery) >= 0.52;
  }

  String _normalizeForSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
  }

  List<String> _tokenizeForSearch(String input) {
    const stopwords = <String>{
      '最近',
      '最远',
      '距离',
      '多远',
      '学校',
      '地址',
      '电话',
      '网站',
      '网址',
      '离我',
      'how',
      'far',
      'distance',
      'nearest',
      'closest',
      'farthest',
      'furthest',
      'from',
      'my',
      'me',
      'school',
      'address',
      'phone',
      'website',
    };

    return input
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
        .map(_normalizeForSearch)
        .where((token) => token.length >= 2 && !stopwords.contains(token))
        .toList(growable: false);
  }

  Set<String> _bigrams(String text) {
    if (text.length < 2) {
      return text.isEmpty ? <String>{} : <String>{text};
    }
    final grams = <String>{};
    for (var i = 0; i < text.length - 1; i++) {
      grams.add(text.substring(i, i + 2));
    }
    return grams;
  }

  double _bigramSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;

    final gramsA = _bigrams(a);
    final gramsB = _bigrams(b);
    if (gramsA.isEmpty || gramsB.isEmpty) return 0;

    final intersection = gramsA.where(gramsB.contains).length;
    final union = gramsA.length + gramsB.length - intersection;
    if (union == 0) return 0;
    return intersection / union;
  }

  List<School> _sortSchools(List<School> schools) {
    final sorted = List<School>.from(schools);
    final byName =
        (School s) => (s.schoolName.isNotEmpty ? s.schoolName : s.address).toLowerCase();

    switch (_sortOption) {
      case _SortOption.nameAsc:
        sorted.sort((a, b) => byName(a).compareTo(byName(b)));
        break;
      case _SortOption.nameDesc:
        sorted.sort((a, b) => byName(b).compareTo(byName(a)));
        break;
      case _SortOption.districtAsc:
        sorted.sort((a, b) {
          final districtCompare =
              a.district.toLowerCase().compareTo(b.district.toLowerCase());
          if (districtCompare != 0) return districtCompare;
          return byName(a).compareTo(byName(b));
        });
        break;
      case _SortOption.distanceAsc:
        if (_currentPosition == null) {
          sorted.sort((a, b) => byName(a).compareTo(byName(b)));
          break;
        }
        sorted.sort((a, b) => _distanceToSchoolMeters(a).compareTo(_distanceToSchoolMeters(b)));
        break;
      case _SortOption.distanceDesc:
        if (_currentPosition == null) {
          sorted.sort((a, b) => byName(a).compareTo(byName(b)));
          break;
        }
        sorted.sort((a, b) => _distanceToSchoolMeters(b).compareTo(_distanceToSchoolMeters(a)));
        break;
    }
    return sorted;
  }

  double _distanceToSchoolMeters(School school) {
    if (_currentPosition == null ||
        school.latitude == null ||
        school.longitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      school.latitude!,
      school.longitude!,
    );
  }

  bool _matchesTypeFilter(School school) {
    if (_selectedType == _allTypes) return true;

    final typeText = school.type.toLowerCase();
    switch (_selectedType) {
      case 'Primary':
        return typeText.contains('primary') || typeText.contains('pri');
      case 'Secondary':
        return typeText.contains('secondary') || typeText.contains('sec');
      case 'Government':
        return typeText.contains('government') || typeText.contains('gov');
      case 'Aided':
        return typeText.contains('aid') || typeText.contains('aided');
      case 'PLK':
        return typeText.contains('plk') || typeText.contains('po leung kuk');
      default:
        final expected = _typeFilters[_selectedType];
        if (expected == null) return true;
        return typeText.contains(expected);
    }
  }

  List<String> _districtOptions(List<School> schools) {
    final districts = schools
        .map((school) => school.district.trim())
        .where((district) => district.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return <String>[_allDistricts, ...districts];
  }

  Map<String, int> _districtCounts(List<School> schools) {
    final counts = <String, int>{};
    for (final school in schools) {
      final district = school.district.trim();
      if (district.isEmpty) continue;
      counts[district] = (counts[district] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _districtRankMap(List<School> schools) {
    final counts = _districtCounts(schools);
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    final rankMap = <String, int>{};
    for (var i = 0; i < sorted.length; i++) {
      rankMap[sorted[i].key] = i + 1;
    }
    return rankMap;
  }

  List<_NearbySchool> _recommendedNearbySchools(List<School> schools) {
    if (_currentPosition == null) return const <_NearbySchool>[];

    final nearby = <_NearbySchool>[];
    for (final school in schools) {
      if (school.latitude == null || school.longitude == null) continue;
      final meters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        school.latitude!,
        school.longitude!,
      );
      nearby.add(_NearbySchool(school: school, distanceMeters: meters));
    }

    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby.take(5).toList(growable: false);
  }

  Widget _buildHeader(int totalCount, int visibleCount, List<School> schools) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0F766E), Color(0xFF115E59)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'HK School Selector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Tooltip(
                message: 'Ask AI',
                child: IconButton(
                  onPressed: () => _openAiAssistant(schools),
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                ),
              ),
              Tooltip(
                message: 'Logout',
                child: IconButton(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$visibleCount of $totalCount schools · user: ${widget.currentUser}',
            style: const TextStyle(color: Color(0xFFD5F5F0), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbySection(List<School> schools) {
    final nearby = _recommendedNearbySchools(schools);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nearby Schools',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLocating ? null : _loadCurrentLocation,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              if (_isLocating)
                const Text('Getting your location...')
              else if (_locationError != null)
                Text(_locationError!, style: const TextStyle(color: Color(0xFFB91C1C)))
              else if (nearby.isEmpty)
                const Text('No nearby recommendations available.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: nearby
                      .map(
                        (item) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7F6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.school.schoolName} · ${item.distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistrictRanking(List<School> schools) {
    final counts = _districtCounts(schools);
    final topDistricts = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    if (topDistricts.isEmpty) return const SizedBox.shrink();
    final top5 = topDistricts.take(5).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'District Ranking (by school count)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: top5.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final item = entry.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$rank ${item.key} (${item.value})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(List<School> schools) {
    final districtOptions = _districtOptions(schools);
    final selectedDistrict = districtOptions.contains(_selectedDistrict)
        ? _selectedDistrict
        : _allDistricts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search by school name',
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                    if (!mounted) return;
                    setState(() {
                      _searchQuery = value;
                    });
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('Favorites only'),
                    selected: _showFavoritesOnly,
                    onSelected: (selected) {
                      setState(() {
                        _showFavoritesOnly = selected;
                      });
                    },
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<_SortOption>(
                      initialValue: _sortOption,
                      decoration: const InputDecoration(labelText: 'Sort by'),
                      items: const <DropdownMenuItem<_SortOption>>[
                        DropdownMenuItem(
                          value: _SortOption.nameAsc,
                          child: Text('Name A-Z'),
                        ),
                        DropdownMenuItem(
                          value: _SortOption.nameDesc,
                          child: Text('Name Z-A'),
                        ),
                        DropdownMenuItem(
                          value: _SortOption.districtAsc,
                          child: Text('District'),
                        ),
                        DropdownMenuItem(
                          value: _SortOption.distanceAsc,
                          child: Text('Distance'),
                        ),
                        DropdownMenuItem(
                          value: _SortOption.distanceDesc,
                          child: Text('Distance (Far)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _sortOption = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 640;

                  final districtDropdown = DropdownButtonFormField<String>(
                    initialValue: selectedDistrict,
                    decoration: const InputDecoration(labelText: 'District'),
                    items: districtOptions
                        .map(
                          (district) => DropdownMenuItem<String>(
                            value: district,
                            child: Text(district),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedDistrict = value;
                      });
                    },
                  );

                  final typeDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: _typeFilters.keys
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedType = value;
                      });
                    },
                  );

                  if (isNarrow) {
                    return Column(
                      children: <Widget>[
                        districtDropdown,
                        const SizedBox(height: 10),
                        typeDropdown,
                      ],
                    );
                  }

                  return Row(
                    children: <Widget>[
                      Expanded(child: districtDropdown),
                      const SizedBox(width: 12),
                      Expanded(child: typeDropdown),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolCard(School school, Map<String, int> districtRankMap) {
    final isFavorite = _favoriteSchoolIds.contains(school.id);
    final title = school.schoolName.isNotEmpty
        ? school.schoolName
        : (school.address.isNotEmpty ? school.address : 'Unknown School');

    final imagePath = _schoolImageService.imagePathForSchool(school, _schoolImageMap);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailScreen(school: school, imageAssetPath: imagePath),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: <Widget>[
                _buildSchoolImage(
                  imagePath,
                  school: school,
                  districtRankMap: districtRankMap,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: <Widget>[
                          _InfoChip(icon: Icons.school_outlined, text: school.type),
                          _InfoChip(icon: Icons.map_outlined, text: school.district),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                  onPressed: () => _toggleFavorite(school),
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolImage(
    String? imagePath, {
    School? school,
    Map<String, int> districtRankMap = const <String, int>{},
  }) {
    if (imagePath == null || imagePath.isEmpty) {
      return _buildImagePlaceholder(
        district: school?.district ?? '',
        rank: districtRankMap[school?.district ?? ''],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        imagePath,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(
          district: school?.district ?? '',
          rank: districtRankMap[school?.district ?? ''],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder({required String district, int? rank}) {
    final rankText = rank == null ? '--' : '#$rank';
    final districtText = district.trim().isEmpty
        ? 'N/A'
        : district.trim().split(' ').map((e) => e.isEmpty ? '' : e[0]).join();

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EEEC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            rankText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F766E),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            districtText.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          height: 86,
          decoration: BoxDecoration(
            color: const Color(0xFFE4ECEA),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EFEE),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(Object? error) {
    return RefreshIndicator(
      onRefresh: _refreshSchools,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 110),
          Icon(
            Icons.cloud_off_rounded,
            color: Colors.blueGrey.shade300,
            size: 42,
          ),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Failed to load schools.\nPull down or tap retry.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: () {
                setState(() {
                  _schoolsFuture = _apiService.fetchSchools();
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 10),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<School>>(
          future: _schoolsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingSkeleton();
            }

            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error);
            }

            final schools = snapshot.data ?? const <School>[];
            if (schools.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refreshSchools,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const <Widget>[
                    SizedBox(height: 120),
                    Center(child: Text('No schools found. Pull down to refresh.')),
                  ],
                ),
              );
            }

            final filteredSchools = _applyFilters(schools);
            final districtRankMap = _districtRankMap(schools);

            return RefreshIndicator(
              onRefresh: _refreshSchools,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filteredSchools.isEmpty ? 5 : filteredSchools.length + 4,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildHeader(schools.length, filteredSchools.length, schools);
                  }
                  if (index == 1) {
                    return _buildNearbySection(schools);
                  }
                  if (index == 2) {
                    return _buildDistrictRanking(schools);
                  }
                  if (index == 3) {
                    return _buildFilters(schools);
                  }

                  if (filteredSchools.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Center(
                        child: Text(
                          'No matching schools found.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }

                  final school = filteredSchools[index - 4];
                  return _buildSchoolCard(school, districtRankMap);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final value = text.trim().isEmpty ? 'N/A' : text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: const Color(0xFF0F766E)),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF374151),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbySchool {
  const _NearbySchool({required this.school, required this.distanceMeters});

  final School school;
  final double distanceMeters;

  double get distanceKm => distanceMeters / 1000;
}

enum _SortOption {
  nameAsc,
  nameDesc,
  districtAsc,
  distanceAsc,
  distanceDesc,
}
