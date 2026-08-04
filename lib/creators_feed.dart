import 'package:flutter/material.dart';
import 'package:whatsapp_stickers_app/page_transitions.dart';
import 'package:whatsapp_stickers_app/auth_service.dart';
import 'package:whatsapp_stickers_app/firestore_service.dart';
import 'package:whatsapp_stickers_app/profile_screen.dart';

/// A data model to represent a creator's profile.
/// This helps in keeping the code clean and type-safe.
class CreatorProfile {
  final String uid;
  final String name;
  final String username;
  final String? coverImageUrl;
  final String? avatarImageUrl;
  final bool isVerified;
  final int followersCount;
  final String bio;
  final List<String> stickerPreviewUrls;
  final bool isFollowing;

  CreatorProfile({
    required this.uid,
    required this.name,
    required this.username,
    this.coverImageUrl,
    this.avatarImageUrl,
    this.isVerified = false,
    this.followersCount = 0,
    this.bio = '',
    this.stickerPreviewUrls = const [],
    this.isFollowing = false,
  });

  /// Factory constructor to create a profile from a map (e.g., from Firestore).
  factory CreatorProfile.fromMap(Map<String, dynamic> map, {bool isFollowing = false}) {
    return CreatorProfile(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      username: map['username'] ?? 'Unknown',
      coverImageUrl: map['coverUrl'],
      avatarImageUrl: map['avatarUrl'],
      isVerified: map['isVerified'] ?? false,
      followersCount: map['followersCount'] ?? 0,
      bio: map['bio'] ?? '',
      stickerPreviewUrls: List<String>.from(map['stickerPreviewUrls'] ?? []),
      isFollowing: isFollowing,
    );
  }

  CreatorProfile copyWith({
    String? uid,
    String? name,
    String? username,
    String? coverImageUrl,
    String? avatarImageUrl,
    bool? isVerified,
    int? followersCount,
    String? bio,
    List<String>? stickerPreviewUrls,
    bool? isFollowing,
  }) {
    return CreatorProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      username: username ?? this.username,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
      isVerified: isVerified ?? this.isVerified,
      followersCount: followersCount ?? this.followersCount,
      bio: bio ?? this.bio,
      stickerPreviewUrls: stickerPreviewUrls ?? this.stickerPreviewUrls,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}

/// This is the main widget for the "Creators" tab.
/// It fetches the list of creators and displays them in a vertical feed.
class CreatorsFeed extends StatefulWidget {
  const CreatorsFeed({super.key});

  @override
  State<CreatorsFeed> createState() => _CreatorsFeedState();
}

class _CreatorsFeedState extends State<CreatorsFeed> {
  bool _isLoading = true;
  List<CreatorProfile> _creators = [];
  final Set<String> _followingInProgress = {};
  final _firestore = FirestoreService.instance;
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _fetchCreators();
  }
  
  Future<void> _fetchCreators() async {
    // --- REAL IMPLEMENTATION ---
    try {
      final currentUid = _auth.currentUid;

      final usersFuture = _firestore.fetchAllUsers();
      final followingFuture = currentUid == null || _auth.isAnonymous
          ? Future.value(<String>[])
          : _firestore.getFollowingIds(currentUid).catchError((_) => <String>[]);

      final results = await Future.wait([usersFuture, followingFuture]);
      final usersData = results[0] as List<Map<String, dynamic>>;
      final followingIds = (results[1] as List<String>).toSet();

      final users = usersData.map((data) {
        final uid = data['uid'] as String? ?? '';
        if (uid == currentUid) return null; // No mostrar el perfil propio en el feed
        return CreatorProfile.fromMap(data, isFollowing: followingIds.contains(uid));
      }).whereType<CreatorProfile>().toList();

      if (mounted) {
        setState(() {
          _creators = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar creadores: $e')));
      }
    }
  }

  Future<void> _toggleFollow(CreatorProfile creator) async {
    final currentUid = _auth.currentUid;
    if (currentUid == null || _auth.isAnonymous || _followingInProgress.contains(creator.uid)) return;

    setState(() => _followingInProgress.add(creator.uid));

    try {
      final isCurrentlyFollowing = creator.isFollowing;
      if (isCurrentlyFollowing) {
        await _firestore.unfollowUser(currentUid, creator.uid);
      } else {
        await _firestore.followUser(currentUid, creator.uid);
      }

      if (mounted) {
        setState(() {
          final index = _creators.indexWhere((c) => c.uid == creator.uid);
          if (index != -1) {
            _creators[index] = creator.copyWith(isFollowing: !isCurrentlyFollowing, followersCount: creator.followersCount + (isCurrentlyFollowing ? -1 : 1));
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al seguir: $e')));
    } finally {
      if (mounted) setState(() => _followingInProgress.remove(creator.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_creators.isEmpty) {
      return const Center(child: Text('No creators found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12.0),
      itemCount: _creators.length,
      itemBuilder: (context, index) {
        final creator = _creators[index];
        return CreatorProfileCard(
          creator: creator,
          isTogglingFollow: _followingInProgress.contains(creator.uid),
          onTap: () {
            // Navigate to the full profile screen when the card is tapped
            Navigator.push(
              context,
              slideUpRoute(ProfileScreen(profileId: creator.uid)),
            ).then((_) => _fetchCreators()); // Recargar al volver por si cambió el estado de 'seguir'
          },
          onFollow: () => _toggleFollow(creator),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 16),
    );
  }
}

/// The reusable card component for a creator's profile preview.
/// It is designed to match your specifications.
class CreatorProfileCard extends StatelessWidget {
  final CreatorProfile creator;
  final VoidCallback onTap;
  final VoidCallback onFollow;
  final bool isTogglingFollow;

  const CreatorProfileCard({
    super.key,
    required this.creator,
    required this.onTap,
    required this.onFollow,
    required this.isTogglingFollow,
  });

  String _formatFollowers(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M Followers';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K Followers';
    }
    return '$count Followers';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: creator.coverImageUrl != null
                      ? Image.network(creator.coverImageUrl!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[300]))
                      : Container(color: Colors.grey[300]),
                ),
                Positioned(
                  bottom: -40,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.cardColor, width: 4)),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: creator.avatarImageUrl != null ? NetworkImage(creator.avatarImageUrl!) : null,
                      backgroundColor: Colors.grey[400],
                      child: creator.avatarImageUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white) : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      creator.name.isNotEmpty ? creator.name : creator.username,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    if (creator.isVerified) ...[const SizedBox(width: 6), const Icon(Icons.verified, color: Colors.blue, size: 20)],
                  ]),
                  const SizedBox(height: 4),
                  Text(_formatFollowers(creator.followersCount), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(creator.bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: creator.stickerPreviewUrls
                    .take(4)
                    .map((url) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(url, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[200], child: const Icon(Icons.hide_image_outlined))),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isTogglingFollow ? null : onFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: creator.isFollowing ? Colors.grey.shade300 : Colors.blue,
                    foregroundColor: creator.isFollowing ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: isTogglingFollow
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(creator.isFollowing ? 'Siguiendo' : 'Seguir',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}