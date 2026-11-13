import 'dart:math' as math;

class LocationUtils {
  // Haversine formula to compute distance in meters between two coordinates
  static double calculateDistanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // in meters
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) {
    return deg * (math.pi / 180.0);
  }

  // Format meters to human readable distance string
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m away';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)}km away';
    }
  }
}
