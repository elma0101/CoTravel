import 'package:cotravel_app/features/join_requests/application/join_request_controller.dart';
import 'package:cotravel_app/features/join_requests/data/join_request_repository.dart';
import 'package:cotravel_app/features/join_requests/domain/trip_join_request.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PreviewTripRepository tripRepository;
  late TripCatalogController tripCatalog;
  late PreviewJoinRequestRepository requestRepository;
  late JoinRequestController requestController;

  setUp(() async {
    final now = DateTime(2026, 8, 5);
    tripRepository = PreviewTripRepository(today: now);
    tripCatalog = TripCatalogController(
      repository: tripRepository,
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
    );
    requestRepository = PreviewJoinRequestRepository(
      tripRepository: tripRepository,
      now: now,
    );
    requestController = JoinRequestController(
      repository: requestRepository,
      userId: 'preview-user',
      profile: const UserProfile.preview(),
      tripCatalog: tripCatalog,
    );
    await tripCatalog.load();
    await requestController.load();
  });

  tearDown(() {
    requestController.dispose();
    tripCatalog.dispose();
  });

  test('host approval waits for traveler confirmation', () async {
    final request = requestController.hostRequests.single;
    final tripBefore = tripCatalog.tripById(request.tripId)!;

    await requestController.reviewAsHost(request, accept: true);

    expect(
      requestController.hostRequests.single.status,
      JoinRequestStatus.pendingTraveler,
    );
    expect(
      tripCatalog.tripById(request.tripId)!.confirmedTravelerCount,
      tripBefore.confirmedTravelerCount,
    );
  });

  test('traveler confirmation locks the seat exactly once', () async {
    final request = requestController.travelerRequests.firstWhere(
      (item) => item.status == JoinRequestStatus.pendingTraveler,
    );

    await requestController.confirmAsTraveler(request, confirm: true);

    final updatedRequest = requestController.travelerRequests.firstWhere(
      (item) => item.id == request.id,
    );
    final updatedTrip = tripCatalog.tripById(request.tripId)!;
    expect(updatedRequest.status, JoinRequestStatus.confirmed);
    expect(updatedTrip.confirmedTravelerCount, 2);
    expect(updatedTrip.openSeats, 2);
  });

  test('traveler can submit and withdraw before host review', () async {
    final trip = tripCatalog.tripById('northern-colors')!;

    final created = await requestController.submitRequest(
      trip: trip,
      message:
          'I enjoy cultural weekends and would be glad to share the planning.',
    );
    expect(created.status, JoinRequestStatus.pendingHost);

    await requestController.withdraw(created);
    final updated = requestController.travelerRequests.firstWhere(
      (item) => item.id == created.id,
    );
    expect(updated.status, JoinRequestStatus.withdrawn);
  });
}
