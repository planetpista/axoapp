import { useState, useEffect, useRef } from 'react';
import { geocodeAddress, calculateRoute, GeoPoint, RouteResult } from '../services/tomtom';

interface UseRouteCalculationArgs {
  pickupAddress: string;
  dropoffAddress: string;
  enabled: boolean;
}

export interface RouteCalculationState {
  pickup: GeoPoint | null;
  dropoff: GeoPoint | null;
  route: RouteResult | null;
  distanceKm: number;
  loading: boolean;
  error: string | null;
}

export const useRouteCalculation = ({
  pickupAddress,
  dropoffAddress,
  enabled,
}: UseRouteCalculationArgs): RouteCalculationState => {
  const [state, setState] = useState<RouteCalculationState>({
    pickup: null,
    dropoff: null,
    route: null,
    distanceKm: 0,
    loading: false,
    error: null,
  });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!enabled || !pickupAddress.trim() || !dropoffAddress.trim()) {
      setState({
        pickup: null,
        dropoff: null,
        route: null,
        distanceKm: 0,
        loading: false,
        error: null,
      });
      return;
    }
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(async () => {
      setState((s) => ({ ...s, loading: true, error: null }));
      const [pickup, dropoff] = await Promise.all([
        geocodeAddress(pickupAddress),
        geocodeAddress(dropoffAddress),
      ]);
      if (!pickup || !dropoff) {
        setState({
          pickup,
          dropoff,
          route: null,
          distanceKm: 0,
          loading: false,
          error: 'Geocoding failed for one or both addresses',
        });
        return;
      }
      const route = await calculateRoute(pickup, dropoff);
      if (!route) {
        setState({
          pickup,
          dropoff,
          route: null,
          distanceKm: 0,
          loading: false,
          error: 'Route calculation failed',
        });
        return;
      }
      setState({
        pickup,
        dropoff,
        route,
        distanceKm: route.distanceKm,
        loading: false,
        error: null,
      });
    }, 700);

    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, [pickupAddress, dropoffAddress, enabled]);

  return state;
};

export default useRouteCalculation;
