abstract final class Routes {
  // Startup
  static const String startup = '/';

  // Auth & Connection
  static const String connection = '/connection';

  // Main tabs (5 items: video, music, photo, reading, mine)
  static const String video = '/video';
  static const String music = '/music';
  static const String photo = '/photo';
  static const String reading = '/reading';
  static const String mine = '/mine';

  // Legacy routes (kept for compatibility)
  static const String files = '/files';
  static const String book = '/book';
  static const String note = '/note';
  static const String settings = '/settings';

  // Sub routes
  static const String videoPlayer = '/video/player';
  static const String musicPlayer = '/music/player';
  static const String photoViewer = '/photo/viewer';
  static const String comicReader = '/comic/reader';
  static const String bookReader = '/book/reader';
  static const String noteEditor = '/note/editor';
}
