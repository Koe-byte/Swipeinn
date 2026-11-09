# Client-Side Proximity Calculation and Zero-Cost Map Rendering

To adhere to the zero-cost requirement without requiring Google Cloud billing or expensive third-party geocoding API keys, Rently stores simple `GeoPoint` coordinates (latitude and longitude) directly on each Listing document. The Flutter client computes approximate distances to pre-defined campus reference pins using the mathematical Haversine formula client-side and renders pins on `flutter_map` using OpenStreetMap tiles. This keeps map rendering fast, battery-efficient, and 100% free.
