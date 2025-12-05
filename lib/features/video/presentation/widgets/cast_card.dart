import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 演员卡片组件
class CastCard extends StatelessWidget {
  const CastCard({
    required this.cast,
    this.onTap,
    this.size = 80,
    super.key,
  });

  final TmdbCast cast;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasProfile = cast.profilePath != null && cast.profilePath!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: hasProfile
                    ? AdaptiveImage(
                        imageUrl: cast.profileUrl,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        placeholder: (_) => _buildPlaceholder(isDark),
                        errorWidget: (_, __) => _buildPlaceholder(isDark),
                      )
                    : _buildPlaceholder(isDark),
              ),
            ),
            const SizedBox(height: 8),
            // 演员名字
            Text(
              cast.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            // 角色名称
            if (cast.character.isNotEmpty)
              Text(
                cast.character,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
      child: Icon(
        Icons.person_rounded,
        size: size * 0.5,
        color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[500],
      ),
    );
}

/// 剧组人员卡片组件 (导演、编剧等)
class CrewCard extends StatelessWidget {
  const CrewCard({
    required this.crew,
    this.onTap,
    this.size = 80,
    super.key,
  });

  final TmdbCrew crew;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasProfile = crew.profilePath != null && crew.profilePath!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: hasProfile
                    ? AdaptiveImage(
                        imageUrl: crew.profileUrl,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        placeholder: (_) => _buildPlaceholder(isDark),
                        errorWidget: (_, __) => _buildPlaceholder(isDark),
                      )
                    : _buildPlaceholder(isDark),
              ),
            ),
            const SizedBox(height: 8),
            // 人员名字
            Text(
              crew.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            // 职位
            Text(
              crew.job,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
      child: Icon(
        Icons.person_rounded,
        size: size * 0.5,
        color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[500],
      ),
    );
}
