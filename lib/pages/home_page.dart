import 'package:flutter/material.dart';
import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/models/playback_session.dart';
import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/pages/video_list_page.dart';
import 'package:empty_player/pages/network_stream_page.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/services/library_repository.dart';
import 'package:empty_player/services/library_preferences_service.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/pages/settings_page.dart';
import 'package:empty_player/pages/about_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:empty_player/components/mini_player.dart';
import 'package:empty_player/components/loading_animation.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DeviceLibraryRepository _libraryRepository =
      const DeviceLibraryRepository();
  final LibraryPreferencesService _libraryPreferences =
      LibraryPreferencesService();
  final PlaybackRepository _playbackRepository =
      SharedPrefsPlaybackRepository();

  List<VideoFolder> _folders = [];
  List<VideoItem> _allVideos = [];
  Set<String> _pinnedFolderPaths = <String>{};
  Set<String> _favoriteMediaIds = <String>{};
  PlaybackState? _lastPlayed;
  String _searchQuery = '';
  LibrarySortOption _sortOption = LibrarySortOption.nameAsc;
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializePreferences();
    _loadVideos();
  }

  Future<void> _initializePreferences() async {
    final pinned = await _libraryPreferences.getPinnedFolders();
    final sort = await _libraryPreferences.getSortOption();
    final lastPlayed = await _playbackRepository.getLastPlayed();
    final favoriteIds = await _playbackRepository.getFavorites();

    if (!mounted) return;
    setState(() {
      _pinnedFolderPaths = pinned;
      _sortOption = sort;
      _lastPlayed = lastPlayed;
      _favoriteMediaIds = favoriteIds;
      _allVideos = _allVideos
          .map(
            (video) =>
                video.copyWith(isFavorite: favoriteIds.contains(video.id)),
          )
          .toList();
    });
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      // Check permission first
      final hasPermission = await _libraryRepository.hasLibraryPermission();

      if (!hasPermission) {
        // Try to request permission
        final status = await _libraryRepository.requestLibraryPermission();

        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _permissionDenied = true;
            });

            // Show dialog if permanently denied
            if (status.isPermanentlyDenied) {
              _showPermissionDialog();
            }
          }
          return;
        }
      }

      // If we have permission, load videos
      final result = await _libraryRepository.getAllVideos();
      final playbackStates = await _playbackRepository.getRecentStates(
        limit: 5000,
      );
      final playbackBySource = <String, PlaybackState>{
        for (final state in playbackStates) state.sourceInput: state,
      };

      if (mounted) {
        setState(() {
          _folders = (result['folders'] as List<VideoFolder>).toList();
          _allVideos = (result['videos'] as List<VideoItem>)
              .map(
                (video) => video.copyWith(
                  lastPositionMs: playbackBySource[video.path]?.positionMs,
                  lastPlayedAt: playbackBySource[video.path]?.updatedAt,
                  playCount: playbackBySource[video.path]?.playCount ?? 0,
                  isFavorite: _favoriteMediaIds.contains(video.id),
                ),
              )
              .toList();
          _isLoading = false;
          _permissionDenied = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _permissionDenied = true;
        });
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Text(
          'Permission Required',
          style: GoogleFonts.lato(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Video access is permanently denied. Please enable it in Settings to view your videos.',
          style: GoogleFonts.lato(color: Colors.grey.shade400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.lato(color: Colors.grey.shade400),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: Text(
              'Open Settings',
              style: GoogleFonts.lato(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<VideoItem> get _visibleVideos {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _allVideos.where((video) {
      if (query.isEmpty) return true;
      return video.name.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case LibrarySortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case LibrarySortOption.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case LibrarySortOption.dateModifiedDesc:
          final aDate =
              a.lastPlayedAt ??
              a.dateModified ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.lastPlayedAt ??
              b.dateModified ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        case LibrarySortOption.sizeDesc:
          return (b.size ?? 0).compareTo(a.size ?? 0);
        case LibrarySortOption.durationDesc:
          return (b.duration ?? Duration.zero).compareTo(
            a.duration ?? Duration.zero,
          );
      }
    });

    return filtered;
  }

  List<VideoFolder> get _visibleFolders {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _folders.where((folder) {
      if (query.isEmpty) return true;
      if (folder.name.toLowerCase().contains(query)) return true;
      return folder.videos.any((v) => v.name.toLowerCase().contains(query));
    }).toList();

    filtered.sort((a, b) {
      final aPinned = _pinnedFolderPaths.contains(a.path);
      final bPinned = _pinnedFolderPaths.contains(b.path);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  String _sortLabel(LibrarySortOption option) {
    switch (option) {
      case LibrarySortOption.nameAsc:
        return 'Name (A-Z)';
      case LibrarySortOption.nameDesc:
        return 'Name (Z-A)';
      case LibrarySortOption.dateModifiedDesc:
        return 'Recent';
      case LibrarySortOption.sizeDesc:
        return 'Size';
      case LibrarySortOption.durationDesc:
        return 'Duration';
    }
  }

  Future<void> _setSortOption(LibrarySortOption option) async {
    setState(() {
      _sortOption = option;
    });
    await _libraryPreferences.setSortOption(option);
  }

  Future<void> _togglePinnedFolder(VideoFolder folder) async {
    await _libraryPreferences.togglePinnedFolder(folder.path);
    final pinned = await _libraryPreferences.getPinnedFolders();
    if (!mounted) return;
    setState(() {
      _pinnedFolderPaths = pinned;
    });
  }

  Future<void> _toggleFavorite(VideoItem video) async {
    final willBeFavorite = !_favoriteMediaIds.contains(video.id);
    await _playbackRepository.setFavorite(video.id, willBeFavorite);
    final favorites = await _playbackRepository.getFavorites();
    if (!mounted) return;

    setState(() {
      _favoriteMediaIds = favorites;
      _allVideos = _allVideos
          .map(
            (v) =>
                v.id == video.id ? v.copyWith(isFavorite: willBeFavorite) : v,
          )
          .toList();
    });
  }

  Future<void> _openLastPlayed() async {
    final lastPlayed = _lastPlayed;
    if (lastPlayed == null) return;

    try {
      final source = MediaSource.fromInput(lastPlayed.sourceInput);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoApp(
            source: source,
            title: lastPlayed.title,
            start: PlaybackStart(position: lastPlayed.position),
          ),
        ),
      );
      final refreshed = await _playbackRepository.getLastPlayed();
      if (mounted) {
        setState(() {
          _lastPlayed = refreshed;
        });
      }
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the last played source.')),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildTabs(),
                const SizedBox(height: 12),
                _buildSearchAndSortBar(),
                if (_lastPlayed != null) ...[
                  const SizedBox(height: 8),
                  _buildContinueWatchingCard(),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _permissionDenied
                      ? _buildPermissionDeniedState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildFoldersView(),
                            _buildAllVideosView(),
                          ],
                        ),
                ),
                const SizedBox(height: 80), // Space for mini player
              ],
            ),
            // Mini player at bottom
            Positioned(left: 0, right: 0, bottom: 0, child: const MiniPlayer()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Library',
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_allVideos.length} videos',
                  style: GoogleFonts.lato(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Settings
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings_outlined, size: 22),
            color: Colors.grey.shade500,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // About
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
            icon: const Icon(Icons.info_outline, size: 22),
            color: Colors.grey.shade500,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () async {
              // Clear cache and reload
              await _libraryRepository.clearCache();
              await _loadVideos();
              await _initializePreferences();
            },
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: Colors.grey.shade500,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NetworkStreamPage(),
                ),
              );
            },
            icon: const Icon(Icons.link_rounded, size: 22),
            color: Colors.grey.shade500,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TabBar(
        controller: _tabController,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: Colors.white, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 0),
        ),
        labelStyle: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        unselectedLabelStyle: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        dividerColor: Colors.grey.shade900,
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: const [
          Tab(text: 'Folders'),
          Tab(text: 'All Videos'),
        ],
      ),
    );
  }

  Widget _buildSearchAndSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: GoogleFonts.lato(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search videos or folders',
                hintStyle: GoogleFonts.lato(color: Colors.grey.shade600),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                filled: true,
                fillColor: Colors.grey.shade900,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<LibrarySortOption>(
            initialValue: _sortOption,
            onSelected: _setSortOption,
            color: Colors.grey.shade900,
            itemBuilder: (context) => LibrarySortOption.values
                .map(
                  (option) => PopupMenuItem<LibrarySortOption>(
                    value: option,
                    child: Text(
                      _sortLabel(option),
                      style: GoogleFonts.lato(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _sortLabel(_sortOption),
                    style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingCard() {
    final lastPlayed = _lastPlayed;
    if (lastPlayed == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openLastPlayed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue watching',
                        style: GoogleFonts.lato(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        lastPlayed.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDuration(lastPlayed.position),
                  style: GoogleFonts.lato(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersView() {
    final folders = _visibleFolders;
    if (folders.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _buildFolderCard(folder);
      },
    );
  }

  Widget _buildFolderCard(VideoFolder folder) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoListPage(folder: folder),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${folder.videoCount} video${folder.videoCount != 1 ? 's' : ''}',
                      style: GoogleFonts.lato(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _togglePinnedFolder(folder),
                icon: Icon(
                  _pinnedFolderPaths.contains(folder.path)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  color: _pinnedFolderPaths.contains(folder.path)
                      ? Colors.white
                      : Colors.grey.shade700,
                  size: 18,
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade700, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllVideosView() {
    final videos = _visibleVideos;
    if (videos.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.7,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _buildVideoCard(video);
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CompactLoadingAnimation(color: Colors.white),
          const SizedBox(height: 24),
          Text(
            'empty player',
            style: GoogleFonts.lato(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanning videos...',
            style: GoogleFonts.lato(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_open_rounded,
              size: 48,
              color: Colors.grey.shade800,
            ),
            const SizedBox(height: 20),
            Text(
              'Storage Access',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow access to display your videos',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _loadVideos,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Grant Access',
                style: GoogleFonts.lato(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(VideoItem video) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          // Play video - navigate to video player
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoApp(
                source: MediaSource.fromInput(video.path),
                title: video.name,
                start: video.lastPositionMs != null
                    ? PlaybackStart(
                        position: Duration(milliseconds: video.lastPositionMs!),
                      )
                    : null,
              ),
            ),
          );
          final refreshed = await _playbackRepository.getLastPlayed();
          if (mounted) {
            setState(() {
              _lastPlayed = refreshed;
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(video),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          _favoriteMediaIds.contains(video.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _favoriteMediaIds.contains(video.id)
                              ? Colors.redAccent
                              : Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  if (video.duration != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(video.duration!),
                          style: GoogleFonts.lato(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.name,
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (video.size != null) ...[
              const SizedBox(height: 2),
              Text(
                _formatFileSize(video.size!),
                style: GoogleFonts.lato(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
            if (video.lastPositionMs != null &&
                video.duration != null &&
                video.lastPositionMs! > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Resume ${_formatDuration(Duration(milliseconds: video.lastPositionMs!))}',
                style: GoogleFonts.lato(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/empty.png',
            width: 80,
            height: 80,
            color: Colors.grey.shade800,
          ),
          const SizedBox(height: 20),
          Text(
            'No videos',
            style: GoogleFonts.lato(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
