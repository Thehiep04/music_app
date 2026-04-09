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
      title: 'Spotify Mini',
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
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF181818),
            selectedIndex: currentTab,
            onDestinationSelected: (index) {
              setState(() {
                currentTab = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
            ],
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

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController(this.tracks);

  final List<Track> tracks;
  final AudioPlayer player = AudioPlayer();
  final List<StreamSubscription> _subscriptions = [];

  bool isLoading = true;
  int currentIndex = 0;
  String query = '';

  Future<void> initialize() async {
    try {
      final playlist = ConcatenatingAudioSource(
        children: tracks
            .map((track) => AudioSource.uri(Uri.parse(track.audioUrl)))
            .toList(),
      );

      await player.setAudioSource(playlist, initialIndex: 0);

      _subscriptions.addAll([
        player.currentIndexStream.listen((index) {
          if (index != null) {
            currentIndex = index;
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
  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;
  Duration get bufferedPosition => player.bufferedPosition;

  List<Track> get featuredTracks => tracks.take(4).toList();
  List<Track> get recentlyPlayed => tracks.reversed.take(4).toList();

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

  Future<void> playTrackByIndex(int index) async {
    if (index < 0 || index >= tracks.length) return;
    try {
      await player.seek(Duration.zero, index: index);
      await player.play();
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
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good evening',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Recently played', actionText: 'See all'),
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
              const SizedBox(height: 24),
              const SectionTitle(title: 'Made for you', actionText: 'More'),
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
                      onTap: () => controller.playSpecificTrack(track),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle(title: 'All songs', actionText: 'Shuffle'),
              const SizedBox(height: 12),
              ...controller.tracks.map(
                    (track) => TrackTile(
                  track: track,
                  isActive: controller.currentTrack?.id == track.id,
                  onTap: () => controller.playSpecificTrack(track),
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final results = controller.filteredTracks;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: controller.setQuery,
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF282828),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                results.isEmpty ? 'No result found' : '${results.length} result(s)',
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
                      onTap: () => controller.playSpecificTrack(track),
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

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final likedSongs = controller.tracks.take(3).toList();
    final recentSongs = controller.recentlyPlayed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Library',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _LibraryBox(
                  icon: Icons.favorite,
                  title: 'Liked Songs',
                  subtitle: '${likedSongs.length} songs',
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
                  title: 'Recently Played',
                  subtitle: '${recentSongs.length} songs',
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

          const SizedBox(height: 20),

          Row(
            children: [
              Text(
                'All Songs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => controller.playTrackByIndex(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play All'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: ListView.separated(
              itemCount: controller.tracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final track = controller.tracks[index];
                return TrackTile(
                  track: track,
                  isActive: controller.currentTrack?.id == track.id,
                  onTap: () => controller.playSpecificTrack(track),
                );
              },
            ),
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      track.imageUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        color: Colors.white12,
                        child: const Icon(Icons.music_note, size: 16),
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
                            height: 1.0,
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
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: controller.previous,
                    icon: const Icon(Icons.skip_previous, size: 20),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    padding: EdgeInsets.zero,
                    onPressed: controller.togglePlayPause,
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      size: 30,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    minHeight: 1.6,
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
            body: Center(child: Text('No track selected')),
          );
        }

        final totalSeconds = controller.duration.inSeconds <= 0
            ? 1.0
            : controller.duration.inSeconds.toDouble();

        final currentSeconds = controller.position.inSeconds
            .clamp(0, controller.duration.inSeconds)
            .toDouble();

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Now Playing'),
            centerTitle: true,
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              children: [
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
                const SizedBox(height: 24),
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
                    const Icon(Icons.favorite_border),
                  ],
                ),
                const SizedBox(height: 18),
                Slider(
                  value: currentSeconds,
                  min: 0,
                  max: totalSeconds,
                  onChanged: controller.seekToSeconds,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(controller.position)),
                    Text(formatDuration(controller.duration)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: controller.previous,
                      icon: const Icon(Icons.skip_previous, size: 38),
                    ),
                    IconButton(
                      onPressed: controller.togglePlayPause,
                      icon: Icon(
                        controller.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        size: 76,
                      ),
                    ),
                    IconButton(
                      onPressed: controller.next,
                      icon: const Icon(Icons.skip_next, size: 38),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.isActive,
  });

  final Track track;
  final VoidCallback onTap;
  final bool isActive;

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
      trailing: Icon(
        isActive ? Icons.equalizer : Icons.play_arrow,
        color: isActive ? const Color(0xFF1DB954) : Colors.white70,
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
  });

  final Track track;
  final VoidCallback onTap;

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
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              track.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54),
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
    audioUrl: '',
    category: 'Soft pop session',
  ),
];