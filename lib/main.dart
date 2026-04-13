import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const SpotifyMiniApp());
}

class SpotifyMiniApp extends StatelessWidget {
  const SpotifyMiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ứng dụng nghe nhạc',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB954),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late final MusicPlayerController controller;
  int currentTab = 0;

  @override
  void initState() {
    super.initState();
    controller = MusicPlayerController(demoTracks);
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: controller),
      SearchScreen(controller: controller),
      LibraryScreen(controller: controller),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
              children: [
                IndexedStack(
                  index: currentTab,
                  children: pages,
                ),
                if (controller.currentTrack != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 84),
                      child: MiniPlayer(
                        controller: controller,
                        onOpen: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NowPlayingScreen(
                                controller: controller,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: AppBottomNav(
            currentTab: currentTab,
            onTap: (index) {
              setState(() {
                currentTab = index;
              });
            },
          ),
        );
      },
    );
  }
}

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String imageUrl;
  final String audioUrl;
  final String category;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.imageUrl,
    required this.audioUrl,
    required this.category,
  });
}

class Playlist {
  final String id;
  String name;
  final List<String> trackIds;

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });
}

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController(this.tracks);

  final List<Track> tracks;
  final AudioPlayer player = AudioPlayer();
  final List<StreamSubscription> _subscriptions = [];
  final List<Track> _history = [];
  final Set<String> likedTrackIds = {};
  final List<Playlist> playlists = [
    Playlist(id: 'pl1', name: 'Playlist yêu thích', trackIds: ['1', '2']),
    Playlist(id: 'pl2', name: 'Chill cuối ngày', trackIds: ['1', '4', '6']),
  ];

  bool isLoading = true;
  int currentIndex = 0;
  String query = '';
  String selectedHomeFilter = 'Tất cả';
  String selectedLibraryFilter = 'Playlist';

  Future<void> initialize() async {
    try {
      final validTracks =
      tracks.where((track) => track.audioUrl.trim().isNotEmpty).toList();

      if (validTracks.isEmpty) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final playlist = ConcatenatingAudioSource(
        children: validTracks
            .map((track) => AudioSource.uri(Uri.parse(track.audioUrl)))
            .toList(),
      );

      await player.setAudioSource(playlist, initialIndex: 0);

      _subscriptions.addAll([
        player.currentIndexStream.listen((index) {
          if (index != null) {
            currentIndex = index;
            final track = currentTrack;
            if (track != null) {
              _pushToHistory(track);
            }
            notifyListeners();
          }
        }),
        player.playerStateStream.listen((_) => notifyListeners()),
        player.positionStream.listen((_) => notifyListeners()),
        player.durationStream.listen((_) => notifyListeners()),
        player.bufferedPositionStream.listen((_) => notifyListeners()),
      ]);
    } catch (e) {
      debugPrint('Initialize audio error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Track? get currentTrack {
    if (tracks.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= tracks.length) return tracks.first;
    return tracks[currentIndex];
  }

  bool get isPlaying => player.playing;
  bool get isShuffled => player.shuffleModeEnabled;
  LoopMode get loopMode => player.loopMode;
  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;
  Duration get bufferedPosition => player.bufferedPosition;

  List<Track> get featuredTracks => tracks.take(4).toList();
  List<Track> get trendingTracks => tracks.reversed.take(4).toList();
  List<Track> get dailyMixTracks => tracks.skip(1).take(4).toList();
  List<Track> get chillTracks =>
      tracks.where((t) => t.category.toLowerCase().contains('chill')).toList();

  List<Track> get recentlyPlayed {
    if (_history.isEmpty) {
      return tracks.take(4).toList();
    }
    return _history.reversed.take(4).toList();
  }

  List<Track> get likedSongs =>
      tracks.where((track) => likedTrackIds.contains(track.id)).toList();

  List<Track> get filteredTracks {
    if (query.trim().isEmpty) return tracks;
    final keyword = query.toLowerCase();
    return tracks.where((track) {
      return track.title.toLowerCase().contains(keyword) ||
          track.artist.toLowerCase().contains(keyword) ||
          track.album.toLowerCase().contains(keyword) ||
          track.category.toLowerCase().contains(keyword);
    }).toList();
  }

  List<Track> get upcomingQueue {
    if (tracks.isEmpty) return [];
    if (currentIndex >= tracks.length - 1) return [];
    return tracks.sublist(currentIndex + 1);
  }

  List<Track> getTracksOfPlaylist(String playlistId) {
    final playlist = playlists.firstWhere((p) => p.id == playlistId);
    return tracks.where((t) => playlist.trackIds.contains(t.id)).toList();
  }

  void _pushToHistory(Track track) {
    _history.removeWhere((t) => t.id == track.id);
    _history.add(track);
  }

  bool isLiked(String trackId) => likedTrackIds.contains(trackId);

  void toggleLike(String trackId) {
    if (likedTrackIds.contains(trackId)) {
      likedTrackIds.remove(trackId);
    } else {
      likedTrackIds.add(trackId);
    }
    notifyListeners();
  }

  void setHomeFilter(String value) {
    selectedHomeFilter = value;
    notifyListeners();
  }

  void setLibraryFilter(String value) {
    selectedLibraryFilter = value;
    notifyListeners();
  }

  void createPlaylist(String name) {
    playlists.insert(
      0,
      Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        trackIds: [],
      ),
    );
    selectedLibraryFilter = 'Playlist';
    notifyListeners();
  }

  void renamePlaylist(String playlistId, String newName) {
    final playlist = playlists.firstWhere((p) => p.id == playlistId);
    playlist.name = newName;
    notifyListeners();
  }

  void deletePlaylist(String playlistId) {
    playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
  }

  void addTrackToPlaylist(String playlistId, String trackId) {
    final playlist = playlists.firstWhere((p) => p.id == playlistId);
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds.add(trackId);
      notifyListeners();
    }
  }

  void removeTrackFromPlaylist(String playlistId, String trackId) {
    final playlist = playlists.firstWhere((p) => p.id == playlistId);
    playlist.trackIds.remove(trackId);
    notifyListeners();
  }

  Future<void> playPlaylist(String playlistId) async {
    final songs = getTracksOfPlaylist(playlistId);
    if (songs.isEmpty) return;
    await playSpecificTrack(songs.first);
  }

  Future<void> playTrackByIndex(int index) async {
    if (index < 0 || index >= tracks.length) return;
    if (tracks[index].audioUrl.trim().isEmpty) return;

    try {
      currentIndex = index;
      _pushToHistory(tracks[index]);
      await player.seek(Duration.zero, index: index);
      await player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Play track error: $e');
    }
  }

  Future<void> playSpecificTrack(Track track) async {
    final index = tracks.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      await playTrackByIndex(index);
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
    } catch (e) {
      debugPrint('Toggle play/pause error: $e');
    }
  }

  Future<void> next() async {
    try {
      if (player.hasNext) {
        await player.seekToNext();
        await player.play();
      }
    } catch (e) {
      debugPrint('Next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      if (player.position.inSeconds > 3) {
        await player.seek(Duration.zero);
        return;
      }

      if (player.hasPrevious) {
        await player.seekToPrevious();
        await player.play();
      }
    } catch (e) {
      debugPrint('Previous error: $e');
    }
  }

  Future<void> seekToSeconds(double value) async {
    try {
      await player.seek(Duration(seconds: value.toInt()));
    } catch (e) {
      debugPrint('Seek error: $e');
    }
  }

  Future<void> toggleShuffle() async {
    try {
      final newValue = !player.shuffleModeEnabled;
      await player.setShuffleModeEnabled(newValue);
      if (newValue) {
        await player.shuffle();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Shuffle error: $e');
    }
  }

  Future<void> cycleRepeatMode() async {
    try {
      if (player.loopMode == LoopMode.off) {
        await player.setLoopMode(LoopMode.all);
      } else if (player.loopMode == LoopMode.all) {
        await player.setLoopMode(LoopMode.one);
      } else {
        await player.setLoopMode(LoopMode.off);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Repeat error: $e');
    }
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final filterLabels = ['Tất cả', 'Nhạc', 'Podcast'];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chào buổi tối',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none),
                  ),
                  const CircleAvatar(
                    backgroundColor: Color(0xFF2A2A2A),
                    child: Icon(Icons.person),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filterLabels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final label = filterLabels[index];
                    final selected = controller.selectedHomeFilter == label;
                    return FilterChipWidget(
                      label: label,
                      selected: selected,
                      onTap: () => controller.setHomeFilter(label),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              const SectionTitle(title: 'Nghe gần đây', actionText: 'Xem tất cả'),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.recentlyPlayed.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 72,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final track = controller.recentlyPlayed[index];
                  return QuickPickCard(
                    track: track,
                    onTap: () => controller.playSpecificTrack(track),
                  );
                },
              ),
              const SizedBox(height: 28),
              const SectionTitle(title: 'Mix hằng ngày', actionText: 'Thêm'),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.dailyMixTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final track = controller.dailyMixTracks[index];
                    return FeaturedCard(
                      track: track,
                      tag: 'Mix #${index + 1}',
                      description: 'Dành riêng cho bạn',
                      onTap: () => controller.playSpecificTrack(track),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              const SectionTitle(title: 'Top thịnh hành', actionText: 'Xem thêm'),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.trendingTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final track = controller.trendingTracks[index];
                    return FeaturedCard(
                      track: track,
                      tag: 'Top ${index + 1}',
                      description: 'Đang được nghe nhiều',
                      onTap: () => controller.playSpecificTrack(track),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              const SectionTitle(title: 'Dành cho bạn', actionText: 'Thêm'),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.featuredTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final track = controller.featuredTracks[index];
                    return FeaturedCard(
                      track: track,
                      tag: 'Gợi ý',
                      description: track.category,
                      onTap: () => controller.playSpecificTrack(track),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              const SectionTitle(title: 'Tất cả bài hát', actionText: 'Phát ngẫu nhiên'),
              const SizedBox(height: 12),
              ...controller.tracks.map(
                    (track) => TrackTile(
                  track: track,
                  isActive: controller.currentTrack?.id == track.id,
                  isLiked: controller.isLiked(track.id),
                  onTap: () => controller.playSpecificTrack(track),
                  onLike: () => controller.toggleLike(track.id),
                  onAddToPlaylist: () => showAddToPlaylistSheet(
                    context,
                    controller: controller,
                    track: track,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final categories = [
      SearchCategoryData('V-Pop', const Color(0xFFAF2896)),
      SearchCategoryData('Chill', const Color(0xFF509BF5)),
      SearchCategoryData('Workout', const Color(0xFF8D67AB)),
      SearchCategoryData('Acoustic', const Color(0xFFE8115B)),
      SearchCategoryData('Lo-fi', const Color(0xFF148A08)),
      SearchCategoryData('US-UK', const Color(0xFFB49BC8)),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final results = controller.filteredTracks;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tìm kiếm',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: controller.setQuery,
                decoration: InputDecoration(
                  hintText: 'Tìm bài hát, ca sĩ, album...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF282828),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (controller.query.trim().isEmpty) ...[
                Text(
                  'Duyệt theo thể loại',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: categories.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      return SearchCategoryCard(item: item);
                    },
                  ),
                ),
              ] else ...[
                Text(
                  results.isEmpty ? 'Không tìm thấy kết quả' : '${results.length} kết quả',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final track = results[index];
                      return TrackTile(
                        track: track,
                        isActive: controller.currentTrack?.id == track.id,
                        isLiked: controller.isLiked(track.id),
                        onTap: () => controller.playSpecificTrack(track),
                        onLike: () => controller.toggleLike(track.id),
                        onAddToPlaylist: () => showAddToPlaylistSheet(
                          context,
                          controller: controller,
                          track: track,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final likedSongs = controller.likedSongs;
        final recentSongs = controller.recentlyPlayed;
        final filters = ['Playlist', 'Album', 'Nghệ sĩ'];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFF2A2A2A),
                    child: Icon(Icons.person, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Thư viện của bạn',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: filters
                    .map(
                      (label) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChipWidget(
                      label: label,
                      selected: controller.selectedLibraryFilter == label,
                      onTap: () => controller.setLibraryFilter(label),
                    ),
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _LibraryBox(
                      icon: Icons.favorite,
                      title: 'Bài hát yêu thích',
                      subtitle: '${likedSongs.length} bài hát',
                      color1: const Color(0xFF5B4BFF),
                      color2: const Color(0xFF8E7CFF),
                      onTap: () {
                        if (likedSongs.isNotEmpty) {
                          controller.playSpecificTrack(likedSongs.first);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LibraryBox(
                      icon: Icons.history,
                      title: 'Nghe gần đây',
                      subtitle: '${recentSongs.length} bài hát',
                      color1: const Color(0xFF1DB954),
                      color2: const Color(0xFF0C7A43),
                      onTap: () {
                        if (recentSongs.isNotEmpty) {
                          controller.playSpecificTrack(recentSongs.first);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.selectedLibraryFilter == 'Playlist'
                          ? 'Playlist của bạn'
                          : controller.selectedLibraryFilter,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (controller.selectedLibraryFilter == 'Playlist')
                    FilledButton.icon(
                      onPressed: () => showCreatePlaylistDialog(
                        context,
                        controller: controller,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Tạo'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: controller.selectedLibraryFilter == 'Playlist'
                    ? ListView.separated(
                  itemCount: controller.playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final playlist = controller.playlists[index];
                    return PlaylistTile(
                      playlist: playlist,
                      trackCount: playlist.trackIds.length,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(
                              controller: controller,
                              playlistId: playlist.id,
                            ),
                          ),
                        );
                      },
                      onPlay: () => controller.playPlaylist(playlist.id),
                      onRename: () => showRenamePlaylistDialog(
                        context,
                        controller: controller,
                        playlist: playlist,
                      ),
                      onDelete: () => controller.deletePlaylist(playlist.id),
                    );
                  },
                )
                    : controller.selectedLibraryFilter == 'Album'
                    ? ListView.builder(
                  itemCount: controller.tracks.length,
                  itemBuilder: (context, index) {
                    final track = controller.tracks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          track.imageUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(track.album),
                      subtitle: Text(track.artist),
                    );
                  },
                )
                    : ListView.builder(
                  itemCount: controller.tracks.length,
                  itemBuilder: (context, index) {
                    final track = controller.tracks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF2A2A2A),
                        child: Icon(Icons.person),
                      ),
                      title: Text(track.artist),
                      subtitle: Text(track.album),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.controller,
    required this.playlistId,
  });

  final MusicPlayerController controller;
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playlist =
        controller.playlists.firstWhere((p) => p.id == playlistId);
        final songs = controller.getTracksOfPlaylist(playlistId);

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2A2A), Color(0xFF121212), Color(0xFF121212)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'rename') {
                              showRenamePlaylistDialog(
                                context,
                                controller: controller,
                                playlist: playlist,
                              );
                            } else if (value == 'delete') {
                              controller.deletePlaylist(playlist.id);
                              Navigator.pop(context);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Đổi tên'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Xóa playlist'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1DB954), Color(0xFF0B5A2A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.queue_music, size: 80),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${songs.length} bài hát',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: songs.isEmpty
                              ? null
                              : () => controller.playPlaylist(playlist.id),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Phát playlist'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: songs.isEmpty
                          ? const Center(
                        child: Text(
                          'Playlist này chưa có bài nào',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                          : ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final track = songs[index];
                          return TrackTile(
                            track: track,
                            isActive:
                            controller.currentTrack?.id == track.id,
                            isLiked: controller.isLiked(track.id),
                            onTap: () => controller.playSpecificTrack(track),
                            onLike: () => controller.toggleLike(track.id),
                            onAddToPlaylist: () => showAddToPlaylistSheet(
                              context,
                              controller: controller,
                              track: track,
                            ),
                            trailingMenu: IconButton(
                              onPressed: () => controller.removeTrackFromPlaylist(
                                playlist.id,
                                track.id,
                              ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LibraryBox extends StatelessWidget {
  const _LibraryBox({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color1,
    required this.color2,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color1;
  final Color color2;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [color1, color2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final MusicPlayerController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      track.imageUrl,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 42,
                        height: 42,
                        color: Colors.white12,
                        child: const Icon(Icons.music_note, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    onPressed: controller.previous,
                    icon: const Icon(Icons.skip_previous, size: 20),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    onPressed: controller.togglePlayPause,
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      size: 32,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    onPressed: controller.next,
                    icon: const Icon(Icons.skip_next, size: 20),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: progress(controller.position, controller.duration),
                    backgroundColor: Colors.white12,
                    color: const Color(0xFF1DB954),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.currentTrack;
        if (track == null) {
          return const Scaffold(
            body: Center(child: Text('Chưa chọn bài hát nào')),
          );
        }

        final totalSeconds = controller.duration.inSeconds <= 0
            ? 1.0
            : controller.duration.inSeconds.toDouble();

        final currentSeconds = controller.position.inSeconds
            .clamp(0, controller.duration.inSeconds)
            .toDouble();

        final isLiked = controller.isLiked(track.id);

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2A2A), Color(0xFF121212), Color(0xFF121212)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                        ),
                        const Expanded(
                          child: Text(
                            'Đang phát',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.network(
                            track.imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.white10,
                                child: const Center(
                                  child: Icon(Icons.music_note, size: 72),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${track.artist} • ${track.album}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => controller.toggleLike(track.id),
                          icon: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? Colors.redAccent : Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbColor: Colors.white,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        overlayColor: Colors.white12,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: currentSeconds,
                        min: 0,
                        max: totalSeconds,
                        onChanged: controller.seekToSeconds,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDuration(controller.position)),
                        Text(formatDuration(controller.duration)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: controller.toggleShuffle,
                          icon: Icon(
                            Icons.shuffle,
                            color: controller.isShuffled
                                ? const Color(0xFF1DB954)
                                : Colors.white70,
                          ),
                        ),
                        IconButton(
                          onPressed: controller.cycleRepeatMode,
                          icon: Icon(
                            controller.loopMode == LoopMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: controller.loopMode == LoopMode.off
                                ? Colors.white70
                                : const Color(0xFF1DB954),
                          ),
                        ),
                        IconButton(
                          onPressed: controller.previous,
                          icon: const Icon(Icons.skip_previous, size: 42),
                        ),
                        IconButton(
                          onPressed: controller.togglePlayPause,
                          icon: Icon(
                            controller.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            size: 78,
                          ),
                        ),
                        IconButton(
                          onPressed: controller.next,
                          icon: const Icon(Icons.skip_next, size: 42),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QueueScreen(controller: controller),
                              ),
                            );
                          },
                          icon: const Icon(Icons.queue_music, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final queue = controller.upcomingQueue;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Danh sách chờ'),
            backgroundColor: Colors.transparent,
          ),
          body: queue.isEmpty
              ? const Center(
            child: Text(
              'Không còn bài nào',
              style: TextStyle(color: Colors.white70),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final track = queue[index];

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    track.imageUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note),
                    ),
                  ),
                ),
                title: Text(
                  track.title,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  track.artist,
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  final realIndex = controller.tracks.indexWhere(
                        (t) => t.id == track.id,
                  );

                  if (realIndex != -1) {
                    controller.playTrackByIndex(realIndex);
                    Navigator.pop(context);
                  }
                },
              );
            },
          ),
        );
      },
    );
  }
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentTab,
    required this.onTap,
  });

  final int currentTab;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: const Color(0xFF181818),
      selectedIndex: currentTab,
      onDestinationSelected: onTap,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Trang chủ',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Tìm kiếm',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music),
          label: 'Thư viện',
        ),
      ],
    );
  }
}

class PlaylistTile extends StatelessWidget {
  const PlaylistTile({
    super.key,
    required this.playlist,
    required this.trackCount,
    required this.onTap,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final int trackCount;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1DB954), Color(0xFF0B5A2A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.queue_music),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$trackCount bài hát',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_fill),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') {
                  onRename();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                PopupMenuItem(value: 'delete', child: Text('Xóa')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.isActive,
    required this.isLiked,
    required this.onLike,
    required this.onAddToPlaylist,
    this.trailingMenu,
  });

  final Track track;
  final VoidCallback onTap;
  final bool isActive;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onAddToPlaylist;
  final Widget? trailingMenu;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          track.imageUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 56,
              height: 56,
              color: Colors.white10,
              child: const Icon(Icons.music_note),
            );
          },
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isActive ? const Color(0xFF1DB954) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${track.artist} • ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onAddToPlaylist,
            icon: const Icon(Icons.playlist_add, color: Colors.white70),
          ),
          IconButton(
            onPressed: onLike,
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? Colors.redAccent : Colors.white70,
            ),
          ),
          trailingMenu ??
              Icon(
                isActive ? Icons.equalizer : Icons.play_arrow,
                color: isActive ? const Color(0xFF1DB954) : Colors.white70,
              ),
        ],
      ),
    );
  }
}

class QuickPickCard extends StatelessWidget {
  const QuickPickCard({
    super.key,
    required this.track,
    required this.onTap,
  });

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: Image.network(
                  track.imageUrl,
                  width: 72,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 72,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note),
                    );
                  },
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.track,
    required this.onTap,
    required this.tag,
    required this.description,
  });

  final Track track;
  final VoidCallback onTap;
  final String tag;
  final String description;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                track.imageUrl,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 120,
                    color: Colors.white10,
                    child: const Center(
                      child: Icon(Icons.music_note),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.actionText,
  });

  final String title;
  final String actionText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          actionText,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class FilterChipWidget extends StatelessWidget {
  const FilterChipWidget({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1DB954) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class SearchCategoryData {
  final String title;
  final Color color;

  const SearchCategoryData(this.title, this.color);
}

class SearchCategoryCard extends StatelessWidget {
  const SearchCategoryCard({super.key, required this.item});

  final SearchCategoryData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          item.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

Future<void> showCreatePlaylistDialog(
    BuildContext context, {
      required MusicPlayerController controller,
    }) async {
  final textController = TextEditingController();

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Tạo playlist'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nhập tên playlist',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                controller.createPlaylist(name);
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Tạo'),
          ),
        ],
      );
    },
  );
}

Future<void> showRenamePlaylistDialog(
    BuildContext context, {
      required MusicPlayerController controller,
      required Playlist playlist,
    }) async {
  final textController = TextEditingController(text: playlist.name);

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Đổi tên playlist'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Tên mới',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                controller.renamePlaylist(playlist.id, name);
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Lưu'),
          ),
        ],
      );
    },
  );
}

void showAddToPlaylistSheet(
    BuildContext context, {
      required MusicPlayerController controller,
      required Track track,
    }) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thêm "${track.title}" vào playlist',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (controller.playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Bạn chưa có playlist nào'),
                    )
                  else
                    ...controller.playlists.map(
                          (playlist) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1DB954), Color(0xFF0B5A2A)],
                            ),
                          ),
                          child: const Icon(Icons.queue_music),
                        ),
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.trackIds.length} bài hát'),
                        onTap: () {
                          controller.addTrackToPlaylist(playlist.id, track.id);
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Đã thêm vào ${playlist.name}'),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await showCreatePlaylistDialog(
                          context,
                          controller: controller,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Tạo playlist mới'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

double progress(Duration current, Duration total) {
  if (total.inMilliseconds == 0) return 0;
  return (current.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
}

const List<Track> demoTracks = [
  Track(
    id: '1',
    title: 'Midnight Flow',
    artist: 'Aurora Pulse',
    album: 'Neon Waves',
    imageUrl: 'https://picsum.photos/id/1011/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    category: 'Chill electronic mix',
  ),
  Track(
    id: '2',
    title: 'Ocean Memory',
    artist: 'Blue District',
    album: 'Skyline Echo',
    imageUrl: 'https://picsum.photos/id/1015/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    category: 'Relax and focus',
  ),
  Track(
    id: '3',
    title: 'Summer Signal',
    artist: 'Nova Echo',
    album: 'Summer Drive',
    imageUrl: 'https://picsum.photos/id/1016/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    category: 'Road trip vibes',
  ),
  Track(
    id: '4',
    title: 'Green Lights',
    artist: 'Metro Bloom',
    album: 'Urban Leaves',
    imageUrl: 'https://picsum.photos/id/1025/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    category: 'Morning playlist',
  ),
  Track(
    id: '5',
    title: 'Night Runner',
    artist: 'Velvet State',
    album: 'After Dark',
    imageUrl: 'https://picsum.photos/id/1035/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    category: 'Late-night energy',
  ),
  Track(
    id: '6',
    title: 'Golden Hour',
    artist: 'Vista 88',
    album: 'Daydream FM',
    imageUrl: 'https://picsum.photos/id/1043/500/500',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    category: 'Soft pop session',
  ),
];
