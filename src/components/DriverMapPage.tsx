import React, { useEffect, useRef, useState } from 'react';
import L from 'leaflet';
import { ArrowLeft, Navigation, MapPin } from 'lucide-react';
import { Currency } from '../types';
import { formatCurrency } from '../utils/currencies';
import { tomtomApiKey, GeoPoint, buildNavigationLink } from '../services/tomtom';

interface DriverMapPageProps {
  onBack: () => void;
  language: 'en' | 'fr';
  currency: Currency;
}

interface Ride {
  id: string;
  pickup: GeoPoint;
  dropoff: GeoPoint;
  distanceKm: number;
  priceEur: number;
  pickupLabel: string;
  dropoffLabel: string;
}

const PER_KM = 0.75;
const PICKUP_FEE = 2;

const SAMPLE_RIDES: { pickup: string; dropoff: string }[] = [
  { pickup: 'Place de la Bastille, Paris', dropoff: 'Gare de Lyon, Paris' },
  { pickup: 'Tour Eiffel, Paris', dropoff: 'Arc de Triomphe, Paris' },
  { pickup: 'Louvre, Paris', dropoff: 'Montmartre, Paris' },
  { pickup: 'Châtelet, Paris', dropoff: 'La Défense, Paris' },
  { pickup: 'Gare du Nord, Paris', dropoff: 'Stade de France, Saint-Denis' },
];

const tr = (lang: 'en' | 'fr', key: string) => {
  const dict: Record<string, { en: string; fr: string }> = {
    availableRides: { en: 'Available Rides', fr: 'Courses Disponibles' },
    price: { en: 'Price', fr: 'Prix' },
    pickup: { en: 'Pickup', fr: 'Départ' },
    dropoff: { en: 'Drop-off', fr: 'Arrivée' },
    distance: { en: 'Distance', fr: 'Distance' },
    launchRoute: { en: 'Launch Route', fr: "Lancer l'Itinéraire" },
    noRides: { en: 'No rides available', fr: 'Aucune course disponible' },
    loading: { en: 'Loading rides…', fr: 'Chargement des courses…' },
  };
  return dict[key]?.[lang] || key;
};

const DriverMapPage: React.FC<DriverMapPageProps> = ({ onBack, language, currency }) => {
  const mapRef = useRef<L.Map | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const markersRef = useRef<L.Marker[]>([]);
  const [rides, setRides] = useState<Ride[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeRide, setActiveRide] = useState<Ride | null>(null);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = L.map(containerRef.current, { center: [48.8566, 2.3522], zoom: 12 });
    L.tileLayer(
      `https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=${tomtomApiKey}`,
      { attribution: '© TomTom', maxZoom: 20 }
    ).addTo(map);
    mapRef.current = map;

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      const resolved: Ride[] = [];
      for (const [idx, sample] of SAMPLE_RIDES.entries()) {
        try {
          const pRes = await fetch(
            `https://api.tomtom.com/search/2/geocode/${encodeURIComponent(sample.pickup)}.json?key=${tomtomApiKey}&countrySet=FR&limit=1`
          );
          const pData = await pRes.json();
          const pItem = pData?.results?.[0];
          const dRes = await fetch(
            `https://api.tomtom.com/search/2/geocode/${encodeURIComponent(sample.dropoff)}.json?key=${tomtomApiKey}&countrySet=FR&limit=1`
          );
          const dData = await dRes.json();
          const dItem = dData?.results?.[0];
          if (!pItem?.position || !dItem?.position) continue;
          const pickup: GeoPoint = {
            lat: pItem.position.lat,
            lon: pItem.position.lon,
            address: pItem.address?.freeformAddress || sample.pickup,
          };
          const dropoff: GeoPoint = {
            lat: dItem.position.lat,
            lon: dItem.position.lon,
            address: dItem.address?.freeformAddress || sample.dropoff,
          };
          const rRes = await fetch(
            `https://api.tomtom.com/routing/1/calculateRoute/${pickup.lat},${pickup.lon}:${dropoff.lat},${dropoff.lon}/json?key=${tomtomApiKey}&routeType=fastest&traffic=true`
          );
          const rData = await rRes.json();
          const distM = rData?.routes?.[0]?.summary?.lengthInMeters ?? 0;
          const distKm = distM / 1000;
          const price = PICKUP_FEE + distKm * PER_KM;
          resolved.push({
            id: `ride-${idx}`,
            pickup,
            dropoff,
            distanceKm: Math.round(distKm * 10) / 10,
            priceEur: Math.round(price * 100) / 100,
            pickupLabel: pickup.address,
            dropoffLabel: dropoff.address,
          });
        } catch {
          // skip on error
        }
      }
      if (!cancelled) {
        setRides(resolved);
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    markersRef.current.forEach((m) => m.remove());
    markersRef.current = [];
    if (rides.length === 0) return;

    const customIcon = L.divIcon({
      className: 'axoxia-marker',
      html: `<div style="background:#2563eb;color:#fff;width:30px;height:30px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.3);border:2px solid #fff"><span style="transform:rotate(45deg);font-weight:700;font-size:14px">€</span></div>`,
      iconSize: [30, 30],
      iconAnchor: [15, 30],
    });

    rides.forEach((ride) => {
      const marker = L.marker([ride.pickup.lat, ride.pickup.lon], { icon: customIcon })
        .addTo(map)
        .on('click', () => setActiveRide(ride));
      markersRef.current.push(marker);
    });

    const bounds = L.latLngBounds(rides.map((r) => [r.pickup.lat, r.pickup.lon]));
    map.fitBounds(bounds.pad(0.2));
  }, [rides]);

  const handleLaunch = (ride: Ride) => {
    const url = buildNavigationLink(ride.dropoff);
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <div className="flex justify-between items-center p-6 bg-white border-b border-gray-200">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-gray-600 hover:text-blue-600 transition-colors"
        >
          <ArrowLeft size={20} />
          <span className="font-medium">{language === 'fr' ? 'Retour' : 'Back'}</span>
        </button>
        <h1 className="text-xl font-bold text-blue-800">{tr(language, 'availableRides')}</h1>
        <div className="w-20" />
      </div>

      <div className="flex-1 relative">
        <div ref={containerRef} className="absolute inset-0 z-0" />

        {/* Rides list overlay */}
        <div className="absolute top-4 right-4 z-[1000] w-80 max-h-[70vh] overflow-y-auto bg-white rounded-lg shadow-xl border border-gray-200">
          <div className="p-4 border-b border-gray-100">
            <div className="flex items-center gap-2 text-blue-800 font-semibold">
              <MapPin size={18} />
              {tr(language, 'availableRides')}
            </div>
          </div>
          {loading ? (
            <div className="p-4 text-sm text-gray-500">{tr(language, 'loading')}</div>
          ) : rides.length === 0 ? (
            <div className="p-4 text-sm text-gray-500">{tr(language, 'noRides')}</div>
          ) : (
            <ul className="divide-y divide-gray-100">
              {rides.map((ride) => (
                <li
                  key={ride.id}
                  onClick={() => {
                    setActiveRide(ride);
                    mapRef.current?.setView([ride.pickup.lat, ride.pickup.lon], 13);
                  }}
                  className={`p-4 cursor-pointer hover:bg-blue-50 transition-colors ${
                    activeRide?.id === ride.id ? 'bg-blue-50' : ''
                  }`}
                >
                  <div className="flex justify-between items-center mb-1">
                    <span className="font-bold text-blue-800">
                      {formatCurrency(ride.priceEur, currency)}
                    </span>
                    <span className="text-xs text-gray-500">{ride.distanceKm} km</span>
                  </div>
                  <p className="text-xs text-gray-600 truncate">
                    <span className="font-medium">{tr(language, 'pickup')}:</span> {ride.pickupLabel}
                  </p>
                  <p className="text-xs text-gray-600 truncate">
                    <span className="font-medium">{tr(language, 'dropoff')}:</span> {ride.dropoffLabel}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* InfoWindow overlay */}
        {activeRide && (
          <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-[1000] w-[min(92vw,420px)] bg-white rounded-xl shadow-2xl border border-gray-200 p-5">
            <div className="flex justify-between items-start mb-3">
              <h3 className="text-lg font-bold text-blue-800">
                {tr(language, 'price')}: {formatCurrency(activeRide.priceEur, currency)}
              </h3>
              <button
                onClick={() => setActiveRide(null)}
                className="text-gray-400 hover:text-gray-600 text-xl leading-none"
                aria-label="Close"
              >
                ×
              </button>
            </div>
            <div className="space-y-2 text-sm">
              <div>
                <span className="font-semibold text-gray-700">{tr(language, 'pickup')}:</span>
                <p className="text-gray-600">{activeRide.pickupLabel}</p>
              </div>
              <div>
                <span className="font-semibold text-gray-700">{tr(language, 'dropoff')}:</span>
                <p className="text-gray-600">{activeRide.dropoffLabel}</p>
              </div>
              <div>
                <span className="font-semibold text-gray-700">{tr(language, 'distance')}:</span>
                <span className="text-gray-600"> {activeRide.distanceKm} km</span>
              </div>
            </div>
            <button
              onClick={() => handleLaunch(activeRide)}
              className="mt-4 w-full flex items-center justify-center gap-2 px-4 py-3 bg-blue-600 text-white font-bold rounded-lg hover:bg-blue-700 transition-colors shadow-md"
            >
              <Navigation size={18} />
              {tr(language, 'launchRoute')}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default DriverMapPage;
