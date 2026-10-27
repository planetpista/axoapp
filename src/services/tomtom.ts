const TOMTOM_API_KEY = 'EH8X1NDWM1vwNLH3dNxpzVBt0u02HtH9';

export interface GeoPoint {
  lat: number;
  lon: number;
  address: string;
}

export interface RouteResult {
  distanceMeters: number;
  travelTimeSeconds: number;
  distanceKm: number;
  geometry: { lat: number; lon: number }[];
}

export const geocodeAddress = async (query: string, countrySet = 'FR,BJ,CN'): Promise<GeoPoint | null> => {
  if (!query.trim()) return null;
  const url = `https://api.tomtom.com/search/2/geocode/${encodeURIComponent(query)}.json`;
  try {
    const res = await fetch(`${url}?key=${TOMTOM_API_KEY}&countrySet=${countrySet}&limit=1`);
    if (!res.ok) return null;
    const data = await res.json();
    const item = data?.results?.[0];
    if (!item?.position) return null;
    return {
      lat: item.position.lat,
      lon: item.position.lon,
      address: item.address?.freeformAddress || query,
    };
  } catch {
    return null;
  }
};

export const calculateRoute = async (from: GeoPoint, to: GeoPoint): Promise<RouteResult | null> => {
  const url = `https://api.tomtom.com/routing/1/calculateRoute/${from.lat},${from.lon}:${to.lat},${to.lon}/json`;
  try {
    const res = await fetch(`${url}?key=${TOMTOM_API_KEY}&routeType=fastest&traffic=true&computeTravelTimeFor=all&instructionsType=tagged`);
    if (!res.ok) return null;
    const data = await res.json();
    const route = data?.routes?.[0];
    if (!route) return null;
    const summary = route.summary;
    const geometry = route.legs?.flatMap((leg: any) =>
      (leg.points || []).map((p: any) => ({ lat: p.latitude, lon: p.longitude }))
    ) || [];
    return {
      distanceMeters: summary.lengthInMeters,
      travelTimeSeconds: summary.travelTimeInSeconds,
      distanceKm: summary.lengthInMeters / 1000,
      geometry,
    };
  } catch {
    return null;
  }
};

export const buildNavigationLink = (to: GeoPoint): string => {
  const dest = `${to.lat},${to.lon}`;
  if (typeof navigator !== 'undefined') {
    const ua = navigator.userAgent || '';
    if (/iphone|ipad|ipod/i.test(ua)) {
      return `maps://?daddr=${dest}`;
    }
    if (/android/i.test(ua)) {
      return `google.navigation:q=${dest}`;
    }
  }
  return `https://www.google.com/maps/dir/?api=1&destination=${dest}`;
};

export const tomtomApiKey = TOMTOM_API_KEY;
