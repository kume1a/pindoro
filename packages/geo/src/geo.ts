export interface LatLng {
  lat: number;
  lon: number;
}

export type Polyline = LatLng[];
export type MultiPolyline = Polyline[];

export const EARTH_RADIUS_M = 6_371_008.8;
const RAD = Math.PI / 180;
const M_PER_DEG = EARTH_RADIUS_M * RAD;

type XY = [x: number, y: number];

export interface LocalProjection {
  project: (p: LatLng) => XY;
  unproject: (xy: XY) => LatLng;
}

// Equirectangular projection in metres around `origin`; accurate to well under 0.5 m at city scale.
export const localProjection = (origin: LatLng): LocalProjection => {
  const kx = M_PER_DEG * Math.cos(origin.lat * RAD);
  return {
    project: (p: LatLng): XY => [(p.lon - origin.lon) * kx, (p.lat - origin.lat) * M_PER_DEG],
    unproject: ([x, y]: XY): LatLng => ({
      lat: origin.lat + y / M_PER_DEG,
      lon: origin.lon + x / kx,
    }),
  };
};

export interface Bbox {
  minLat: number;
  minLon: number;
  maxLat: number;
  maxLon: number;
}

export const bboxOf = (line: Polyline): Bbox => {
  const b = { minLat: Infinity, minLon: Infinity, maxLat: -Infinity, maxLon: -Infinity };
  for (const p of line) {
    b.minLat = Math.min(b.minLat, p.lat);
    b.minLon = Math.min(b.minLon, p.lon);
    b.maxLat = Math.max(b.maxLat, p.lat);
    b.maxLon = Math.max(b.maxLon, p.lon);
  }
  return b;
};

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

export interface NearestPoint {
  distanceMeters: number;
  nearestPoint: LatLng;
}

// Distance to the closest point on any SEGMENT (not vertex) of a multi-polyline.
// The projection is axis-aligned, so clamping into a part's lat/lon bbox gives an exact lower bound.
export const pointToPolylineDistance = (point: LatLng, lines: MultiPolyline): NearestPoint => {
  const proj = localProjection(point);
  let best = Infinity;
  let bestXY: XY = [0, 0];
  for (const line of lines) {
    if (line.length === 0) continue;
    const b = bboxOf(line);
    const [bx, by] = proj.project({
      lat: clamp(point.lat, b.minLat, b.maxLat),
      lon: clamp(point.lon, b.minLon, b.maxLon),
    });
    if (Math.hypot(bx, by) >= best) continue;
    const xy = line.map(proj.project);
    for (let i = 0; i < xy.length; i++) {
      const [ax, ay] = xy[i] as XY;
      const [cx, cy] = xy[Math.min(i + 1, xy.length - 1)] as XY;
      const dx = cx - ax;
      const dy = cy - ay;
      const len2 = dx * dx + dy * dy;
      const t = len2 === 0 ? 0 : clamp(-(ax * dx + ay * dy) / len2, 0, 1);
      const px = ax + t * dx;
      const py = ay + t * dy;
      const d = Math.hypot(px, py);
      if (d < best) {
        best = d;
        bestXY = [px, py];
      }
    }
  }
  if (best === Infinity) throw new RangeError("pointToPolylineDistance: empty polyline");
  return { distanceMeters: best, nearestPoint: proj.unproject(bestXY) };
};

// Google polyline algorithm at 1e6 precision, (lat, lon) order.
// Rounds half away from zero so Dart's num.round() produces identical strings.
const roundHalfAway = (v: number): number => Math.sign(v) * Math.round(Math.abs(v));

const encodeValue = (v: number): string => {
  let n = v < 0 ? ~(v << 1) : v << 1;
  let out = "";
  while (n >= 0x20) {
    out += String.fromCharCode((0x20 | (n & 0x1f)) + 63);
    n >>= 5;
  }
  return out + String.fromCharCode(n + 63);
};

export const encodePolyline6 = (points: Polyline): string => {
  let out = "";
  let prevLat = 0;
  let prevLon = 0;
  for (const p of points) {
    const lat = roundHalfAway(p.lat * 1e6);
    const lon = roundHalfAway(p.lon * 1e6);
    out += encodeValue(lat - prevLat) + encodeValue(lon - prevLon);
    prevLat = lat;
    prevLon = lon;
  }
  return out;
};

export const decodePolyline6 = (encoded: string): Polyline => {
  const points: Polyline = [];
  let i = 0;
  let lat = 0;
  let lon = 0;
  const next = (): number => {
    let result = 0;
    let shift = 0;
    let b: number;
    do {
      b = encoded.charCodeAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 ? ~(result >> 1) : result >> 1;
  };
  while (i < encoded.length) {
    lat += next();
    lon += next();
    points.push({ lat: lat / 1e6, lon: lon / 1e6 });
  }
  return points;
};
