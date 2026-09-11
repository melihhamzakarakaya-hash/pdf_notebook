String formatRelativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  if (diff.inDays == 1) return 'dün';
  if (diff.inDays < 7) return '${diff.inDays} gün önce';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} hafta önce';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} ay önce';
  return '${(diff.inDays / 365).floor()} yıl önce';
}
