import { useState, useEffect } from 'react';
import { ShippingData, Currency } from '../types';
import { convertCurrency, currencies } from '../utils/currencies';
import { PRICING, PARCEL_SIZES, MOVING_SIZES, Size } from '../utils/shippingConfig';

export interface CostBreakdown {
  base: number;
  size: number;
  distance: number;
  weight: number;
  pickup: number;
  insurance: number;
  total: number;
}

const getSizeSurcharge = (category: string, size: Size): number => {
  if (!size) return 0;
  if (category === 'Parcel') {
    return PARCEL_SIZES.find((s) => s.id === size)?.surcharge ?? 0;
  }
  if (category === 'Moving') {
    return MOVING_SIZES.find((s) => s.id === size)?.surcharge ?? 0;
  }
  return 0;
};

export const useShippingCalculator = (
  shippingData: ShippingData,
  currency: Currency
): CostBreakdown => {
  const [costs, setCosts] = useState<CostBreakdown>({
    base: 0,
    size: 0,
    distance: 0,
    weight: 0,
    pickup: 0,
    insurance: 0,
    total: 0,
  });

  useEffect(() => {
    const calc = () => {
      let base = 0;
      let sizeFee = 0;
      let distanceFee = 0;
      let weightFee = 0;
      let pickup = 0;

      const { category, weight, distance, size } = shippingData;

      if (category === 'Mail') {
        base = PRICING.mail.flatFee;
      } else if (category === 'Parcel') {
        pickup = PRICING.parcel.pickupFee;
        sizeFee = getSizeSurcharge('Parcel', size as Size);
        if (distance > 0) distanceFee = distance * PRICING.parcel.perKm;
        if (weight > 0) weightFee = weight * PRICING.parcel.perKm;
      } else if (category === 'Moving') {
        base = PRICING.moving.baseFee;
        sizeFee = getSizeSurcharge('Moving', size as Size);
        if (distance > 0) distanceFee = distance * PRICING.moving.perKm;
      } else if (category === 'Export') {
        if (weight > 0) weightFee = weight * PRICING.export.perKg;
      }

      const subTotal = base + sizeFee + distanceFee + weightFee + pickup;
      const insurance = shippingData.insurance ? subTotal * 0.2 : 0;
      const totalEur = subTotal + insurance;

      const conv = (v: number) => convertCurrency(v, currencies[0], currency);

      setCosts({
        base: conv(base),
        size: conv(sizeFee),
        distance: conv(distanceFee),
        weight: conv(weightFee),
        pickup: conv(pickup),
        insurance: conv(insurance),
        total: conv(totalEur),
      });
    };

    calc();
  }, [shippingData, currency]);

  return costs;
};

export default useShippingCalculator;
