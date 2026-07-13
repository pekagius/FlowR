# WindFlow — native iOS Windy clone

WindFlow is a native iOS app (SwiftUI + MapKit, zero third-party dependencies) that recreates the
feature set of [Windy.com](https://www.windy.com): an animated wind-particle map, 35+ weather
overlays, multiple forecast models, a scrubbable 7–10 day timeline, point forecasts with
meteogram/airgram/sounding, waves, air quality, radar & satellite, a hurricane tracker, weather
warnings, webcams, favorites and configurable units.

> WindFlow is an independent project inspired by Windy.com and is not affiliated with Windyty SE.
> It uses no Windy assets or branding — all weather data comes from open/free APIs.

## Feature map (Windy → WindFlow)

| Windy feature | WindFlow implementation |
|---|---|
| Animated wind particle map | CPU particle engine advected by a live wind grid, drawn with SwiftUI `Canvas` over MapKit (`MapEngine/ParticleLayer.swift`) |
| 50+ color overlays (wind, gusts, temp, rain, clouds, pressure, CAPE, UV, visibility, freezing level, …) | 35+ layers rendered as interpolated heatmaps via a custom `MKOverlayRenderer` (`MapEngine/HeatmapOverlay.swift`), Windy-style color ramps in `MapEngine/ColorScale.swift` |
| Altitude slider (surface → FL) | Pressure-level picker (surface, 950…200 hPa) for wind / temperature / humidity |
| Weather model picker (ECMWF, GFS, ICON, AROME, …) | Open-Meteo multi-model API: Best match, ECMWF, GFS, ICON/-EU/-D2, GEM, AROME/ARPEGE, UKMO, JMA |
| Timeline with play animation | Scrubbable + animatable timeline; heatmap, particles and radar frames follow it |
| Point forecast (tap anywhere) | Bottom sheet with 10-day daily strip + 48 h hourly table |
| Meteogram | Multi-panel Swift Charts view (clouds, temp/dew point, precipitation, wind/gusts) |
| Airgram | Time × altitude wind/cloud matrix (Canvas) |
| Sounding | Vertical temperature/dew-point profile from pressure-level data, time-scrubbable |
| Waves / swell / currents / SST | Open-Meteo Marine API layers + Waves tab |
| Tides | Sea-level (tide) map layer + Tides tab: tide curve, high/low water times & heights (parabolic extremum refinement), tidal range, plus live water level **and water temperature** from the nearest official PEGELONLINE/WSV gauge (German coast, e.g. Büsum) |
| Air quality (PM2.5, PM10, NO₂, O₃, SO₂, CO, dust, AOD, AQI) | Open-Meteo Air Quality API layers + detail tab |
| Weather radar + satellite | RainViewer tiles (radar past + nowcast, IR satellite) with frame animation |
| Hurricane tracker | NOAA/NHC active storms plotted on the map |
| Severe weather warnings | US NWS + German DWD warnings (Bright Sky) for the selected point |
| Observed conditions | Live measurement from the nearest DWD station (Bright Sky): temp, wind, pressure |
| Ensemble forecast | ~30-member ICON/GFS ensemble plume: median, middle-50 % band, full spread (forecast confidence) |
| Weather history | Last 31 days observed: daily min–max temp, precipitation, max wind + extremes summary |
| Sun & moon | Sunrise/sunset, daylight duration, computed moon phase + illumination |
| Pollen | Grass/birch/alder/mugwort/olive/ragweed (CAMS, Europe) — map layers + detail grid |
| Aviation weather | Live METAR + TAF from the nearest airports (NOAA AWC), flight category badges |
| Satellite (visible) | NASA GIBS VIIRS true-color imagery, daily frames scrubbable over the last 8 days |
| Webcams | Windy Webcams API v3 client (bring your own free API key in Settings) |
| Model comparison | Per-model chart (temp/wind/gusts/rain) across 6 global models |
| Search & favorites | Open-Meteo geocoding, favorites + recents persisted locally |
| Units & settings | kt/bft/m/s/km/h/mph, °C/°F, hPa/inHg/mmHg, mm/in, m/ft, base map styles, overlay opacity, particle density, dark mode |

Not feasible with free/open data and therefore omitted: lightning strike detection, global
government warnings, paragliding/kite spot database, and Windy's premium 1-h global updates.

## Data sources (all free, no key required unless noted)

- **Open-Meteo** — forecast, marine, air-quality and geocoding APIs (non-commercial free tier)
- **RainViewer** — radar + IR satellite tile frames
- **NOAA / NHC** — `CurrentStorms.json` hurricane feed
- **US NWS** — `api.weather.gov` active alerts
- **Bright Sky** — DWD open data (German warnings + station observations), no key
- **NOAA AWC** — `aviationweather.gov` METAR/TAF, no key
- **NASA GIBS** — VIIRS true-color satellite tiles, no key
- **BigDataCloud** — client-side reverse geocoding for tapped points, no key
- **PEGELONLINE (WSV)** — official German live water-level gauges, open data, no key
- **Windy Webcams API** — optional, free key, entered in Settings

## Building

1. Open `ios/WindFlow/WindFlow.xcodeproj` in Xcode 16 or newer.
2. Select the *WindFlow* scheme and an iOS 17+ simulator or device.
3. Run. No package resolution, API keys or signing tweaks needed (automatic signing).

The grid fetch batches ~230 grid points per layer/region from Open-Meteo; heavy panning across
many layers can hit the free-tier daily quota — responses are cached (URLCache + in-memory grid
LRU) to keep usage low.

## Architecture

```
WindFlow/
├── WindFlowApp.swift          App entry, environment objects
├── Models/                    Layers, units, forecast structures, places, storms/alerts/webcams
├── Services/                  Open-Meteo clients, grid fetcher (actor), RainViewer, NHC, NWS,
│                              webcams, CoreLocation
├── MapEngine/                 Color ramps, weather grid + interpolation, heatmap MKOverlay,
│                              particle engine + Canvas layer
└── Views/                     Map screen (MKMapView wrapper), floating controls, layer picker,
                               timeline, point-forecast sheet, charts, search, settings, webcams
```

State flows through `AppState` (@MainActor ObservableObject): layer/model/altitude/timeline
selection triggers grid refetches; the map coordinator syncs overlays; the particle canvas and
heatmap renderer both sample the same `WeatherGrid` (bilinear in space, linear in time).
