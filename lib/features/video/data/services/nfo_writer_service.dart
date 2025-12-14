import 'dart:convert';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// NFO 文件类型
enum NfoType {
  /// 电影 NFO (movie.nfo 或 {videoname}.nfo)
  movie,

  /// 电视剧 NFO (tvshow.nfo)
  tvShow,

  /// 剧集 NFO ({videoname}.nfo)
  episode,
}

/// NFO 文件生成和写入服务
///
/// 生成 Kodi/Jellyfin/Plex 兼容的标准 NFO XML 文件
class NfoWriterService {
  /// 生成电影 NFO 内容
  ///
  /// 遵循 Kodi 标准 NFO 格式
  /// 参考: https://kodi.wiki/view/NFO_files/Movies
  String generateMovieNfo({
    required String title,
    String? originalTitle,
    int? year,
    double? rating,
    String? plot,
    int? tmdbId,
    String? imdbId,
    List<String>? genres,
    int? runtime,
    String? premiered,
    String? director,
    String? studio,
    String? tagline,
    int? collectionId,
    String? collectionName,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<movie>')
      ..writeln('  <title>${_escapeXml(title)}</title>');

    if (originalTitle != null && originalTitle != title) {
      buffer.writeln('  <originaltitle>${_escapeXml(originalTitle)}</originaltitle>');
    }

    if (year != null) {
      buffer.writeln('  <year>$year</year>');
    }

    if (rating != null && rating > 0) {
      buffer
        ..writeln('  <ratings>')
        ..writeln('    <rating name="themoviedb" max="10">')
        ..writeln('      <value>$rating</value>')
        ..writeln('    </rating>')
        ..writeln('  </ratings>');
    }

    if (plot != null && plot.isNotEmpty) {
      buffer.writeln('  <plot>${_escapeXml(plot)}</plot>');
    }

    if (tagline != null && tagline.isNotEmpty) {
      buffer.writeln('  <tagline>${_escapeXml(tagline)}</tagline>');
    }

    if (runtime != null && runtime > 0) {
      buffer.writeln('  <runtime>$runtime</runtime>');
    }

    if (premiered != null && premiered.isNotEmpty) {
      buffer.writeln('  <premiered>$premiered</premiered>');
    }

    if (director != null && director.isNotEmpty) {
      buffer.writeln('  <director>${_escapeXml(director)}</director>');
    }

    if (studio != null && studio.isNotEmpty) {
      buffer.writeln('  <studio>${_escapeXml(studio)}</studio>');
    }

    if (genres != null) {
      for (final genre in genres) {
        buffer.writeln('  <genre>${_escapeXml(genre)}</genre>');
      }
    }

    if (collectionId != null || collectionName != null) {
      buffer.writeln('  <set>');
      if (collectionName != null) {
        buffer.writeln('    <name>${_escapeXml(collectionName)}</name>');
      }
      if (collectionId != null) {
        buffer.writeln('    <tmdbcolid>$collectionId</tmdbcolid>');
      }
      buffer.writeln('  </set>');
    }

    // TMDB ID
    if (tmdbId != null) {
      buffer
        ..writeln('  <tmdbid>$tmdbId</tmdbid>')
        ..writeln('  <uniqueid type="tmdb">$tmdbId</uniqueid>');
    }

    // IMDb ID
    if (imdbId != null && imdbId.isNotEmpty) {
      buffer
        ..writeln('  <imdbid>$imdbId</imdbid>')
        ..writeln('  <uniqueid type="imdb" default="true">$imdbId</uniqueid>');
    }

    buffer.writeln('</movie>');

    return buffer.toString();
  }

  /// 生成电视剧 NFO 内容
  ///
  /// 遵循 Kodi 标准 NFO 格式
  /// 参考: https://kodi.wiki/view/NFO_files/TV_shows
  String generateTvShowNfo({
    required String title,
    String? originalTitle,
    int? year,
    double? rating,
    String? plot,
    int? tmdbId,
    String? imdbId,
    List<String>? genres,
    int? runtime,
    String? premiered,
    String? status,
    String? network,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<tvshow>')
      ..writeln('  <title>${_escapeXml(title)}</title>');

    if (originalTitle != null && originalTitle != title) {
      buffer.writeln('  <originaltitle>${_escapeXml(originalTitle)}</originaltitle>');
    }

    if (year != null) {
      buffer.writeln('  <year>$year</year>');
    }

    if (rating != null && rating > 0) {
      buffer
        ..writeln('  <ratings>')
        ..writeln('    <rating name="themoviedb" max="10">')
        ..writeln('      <value>$rating</value>')
        ..writeln('    </rating>')
        ..writeln('  </ratings>');
    }

    if (plot != null && plot.isNotEmpty) {
      buffer.writeln('  <plot>${_escapeXml(plot)}</plot>');
    }

    if (runtime != null && runtime > 0) {
      buffer.writeln('  <runtime>$runtime</runtime>');
    }

    if (premiered != null && premiered.isNotEmpty) {
      buffer.writeln('  <premiered>$premiered</premiered>');
    }

    if (status != null && status.isNotEmpty) {
      buffer.writeln('  <status>${_escapeXml(status)}</status>');
    }

    if (network != null && network.isNotEmpty) {
      buffer.writeln('  <studio>${_escapeXml(network)}</studio>');
    }

    if (genres != null) {
      for (final genre in genres) {
        buffer.writeln('  <genre>${_escapeXml(genre)}</genre>');
      }
    }

    // TMDB ID
    if (tmdbId != null) {
      buffer
        ..writeln('  <tmdbid>$tmdbId</tmdbid>')
        ..writeln('  <uniqueid type="tmdb">$tmdbId</uniqueid>');
    }

    // IMDb ID
    if (imdbId != null && imdbId.isNotEmpty) {
      buffer
        ..writeln('  <imdbid>$imdbId</imdbid>')
        ..writeln('  <uniqueid type="imdb" default="true">$imdbId</uniqueid>');
    }

    buffer.writeln('</tvshow>');

    return buffer.toString();
  }

  /// 生成剧集 NFO 内容
  ///
  /// 遵循 Kodi 标准 NFO 格式
  /// 参考: https://kodi.wiki/view/NFO_files/Episodes
  String generateEpisodeNfo({
    required String title,
    int? season,
    int? episode,
    double? rating,
    String? plot,
    int? tmdbId,
    String? aired,
    int? runtime,
    String? director,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<episodedetails>')
      ..writeln('  <title>${_escapeXml(title)}</title>');

    if (season != null) {
      buffer.writeln('  <season>$season</season>');
    }

    if (episode != null) {
      buffer.writeln('  <episode>$episode</episode>');
    }

    if (rating != null && rating > 0) {
      buffer
        ..writeln('  <ratings>')
        ..writeln('    <rating name="themoviedb" max="10">')
        ..writeln('      <value>$rating</value>')
        ..writeln('    </rating>')
        ..writeln('  </ratings>');
    }

    if (plot != null && plot.isNotEmpty) {
      buffer.writeln('  <plot>${_escapeXml(plot)}</plot>');
    }

    if (aired != null && aired.isNotEmpty) {
      buffer.writeln('  <aired>$aired</aired>');
    }

    if (runtime != null && runtime > 0) {
      buffer.writeln('  <runtime>$runtime</runtime>');
    }

    if (director != null && director.isNotEmpty) {
      buffer.writeln('  <director>${_escapeXml(director)}</director>');
    }

    if (tmdbId != null) {
      buffer.writeln('  <uniqueid type="tmdb">$tmdbId</uniqueid>');
    }

    buffer.writeln('</episodedetails>');

    return buffer.toString();
  }

  /// 从 TMDB 电影详情生成 NFO 内容
  String generateFromTmdbMovie(TmdbMovieDetail movie) {
    // 解析 releaseDate 字符串为年份
    int? year;
    if (movie.releaseDate.isNotEmpty) {
      year = int.tryParse(movie.releaseDate.split('-').first);
    }

    // 获取导演
    final director = movie.director?.name;

    // 获取制作公司（第一个）
    final studio = movie.productionCompanies.isNotEmpty
        ? movie.productionCompanies.first.name
        : null;

    return generateMovieNfo(
      title: movie.title,
      originalTitle: movie.originalTitle,
      year: year,
      rating: movie.voteAverage,
      plot: movie.overview,
      tmdbId: movie.id,
      genres: movie.genres.map((g) => g.name).toList(),
      runtime: movie.runtime,
      premiered: movie.releaseDate.isNotEmpty ? movie.releaseDate : null,
      director: director,
      studio: studio,
      tagline: movie.tagline,
      collectionId: movie.belongsToCollection?.id,
      collectionName: movie.belongsToCollection?.name,
    );
  }

  /// 从 TMDB 电视剧详情生成 NFO 内容
  String generateFromTmdbTvShow(TmdbTvDetail tvShow) {
    // 解析 firstAirDate 字符串为年份
    int? year;
    if (tvShow.firstAirDate.isNotEmpty) {
      year = int.tryParse(tvShow.firstAirDate.split('-').first);
    }

    // 获取电视网（第一个）
    final network = tvShow.networks.isNotEmpty
        ? tvShow.networks.first.name
        : null;

    return generateTvShowNfo(
      title: tvShow.name,
      originalTitle: tvShow.originalName,
      year: year,
      rating: tvShow.voteAverage,
      plot: tvShow.overview,
      tmdbId: tvShow.id,
      genres: tvShow.genres.map((g) => g.name).toList(),
      runtime: tvShow.episodeRunTime.isNotEmpty ? tvShow.episodeRunTime.first : null,
      premiered: tvShow.firstAirDate.isNotEmpty ? tvShow.firstAirDate : null,
      status: tvShow.status,
      network: network,
    );
  }

  /// 写入 NFO 文件到远程目录
  ///
  /// [fileSystem] 远程文件系统
  /// [videoDir] 视频所在目录
  /// [nfoContent] NFO 内容
  /// [type] NFO 类型
  /// [videoFileName] 视频文件名（用于生成单独的 NFO 文件名）
  ///
  /// 返回写入的 NFO 文件路径
  Future<String?> writeNfoFile({
    required NasFileSystem fileSystem,
    required String videoDir,
    required String nfoContent,
    required NfoType type,
    String? videoFileName,
  }) async {
    try {
      final nfoFileName = _getNfoFileName(type, videoFileName);
      final nfoPath = videoDir.endsWith('/') ? '$videoDir$nfoFileName' : '$videoDir/$nfoFileName';

      logger.d('NfoWriterService: 写入 NFO 文件到 $nfoPath');

      final data = utf8.encode(nfoContent);
      await fileSystem.writeFile(nfoPath, data);

      logger.i('NfoWriterService: NFO 文件写入成功');
      return nfoPath;
    } on Exception catch (e, st) {
      logger.w('NfoWriterService: NFO 文件写入失败', e, st);
      return null;
    }
  }

  /// 获取 NFO 文件名
  String _getNfoFileName(NfoType type, String? videoFileName) {
    switch (type) {
      case NfoType.movie:
        // 电影: 如果提供了视频文件名，使用 {videoname}.nfo，否则使用 movie.nfo
        if (videoFileName != null && videoFileName.isNotEmpty) {
          final baseName = _removeExtension(videoFileName);
          return '$baseName.nfo';
        }
        return 'movie.nfo';

      case NfoType.tvShow:
        // 电视剧: 总是使用 tvshow.nfo
        return 'tvshow.nfo';

      case NfoType.episode:
        // 剧集: 使用 {videoname}.nfo
        if (videoFileName != null && videoFileName.isNotEmpty) {
          final baseName = _removeExtension(videoFileName);
          return '$baseName.nfo';
        }
        return 'episode.nfo';
    }
  }

  /// 移除文件扩展名
  String _removeExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  /// XML 转义
  String _escapeXml(String text) => text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
}

