String formatTripDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]}';
}

String formatTripDateRange(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month) {
    final month = formatTripDate(start).split(' ').last;
    return '${start.day}-${end.day} $month ${end.year}';
  }
  return '${formatTripDate(start)} - ${formatTripDate(end)} ${end.year}';
}

String formatTripMoney(double value, String currency) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return '${buffer.toString()} $currency';
}
