import '../../trips/domain/trip.dart';

/// Links that open a provider's own search with the trip already filled in.
/// CoTravel has no partnership with these providers and takes no commission.
class BookingSearchLinks {
  const BookingSearchLinks({
    required this.airbnb,
    required this.booking,
    required this.directions,
  });

  factory BookingSearchLinks.forTrip(Trip trip) {
    final place = trip.destinationCity;
    final checkIn = _date(trip.startDate);
    final checkOut = _date(
      // A one-day trip still needs a checkout after the check-in.
      trip.endDate.isAfter(trip.startDate)
          ? trip.endDate
          : trip.startDate.add(const Duration(days: 1)),
    );
    final guests = '${trip.capacity}';
    return BookingSearchLinks(
      airbnb: Uri.https('www.airbnb.com', '/s/$place/homes', {
        'checkin': checkIn,
        'checkout': checkOut,
        'adults': guests,
      }),
      booking: Uri.https('www.booking.com', '/searchresults.html', {
        'ss': place,
        'checkin': checkIn,
        'checkout': checkOut,
        'group_adults': guests,
      }),
      directions: Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'origin': trip.originCity,
        'destination': place,
      }),
    );
  }

  final Uri airbnb;
  final Uri booking;
  final Uri directions;

  static String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
