import React from 'react';
import { Currency } from '../types';
import { formatCurrency } from '../utils/currencies';
import { CostBreakdown } from '../hooks/useShippingCalculator';

interface CostSummaryProps {
  costs: CostBreakdown;
  currency: Currency;
  translations: any;
}

const CostSummary: React.FC<CostSummaryProps> = ({ costs, currency, translations }) => {
  const rows: { label: string; value: number }[] = [];
  if (costs.base > 0) rows.push({ label: translations.baseFee, value: costs.base });
  if (costs.pickup > 0) rows.push({ label: translations.pickupFee, value: costs.pickup });
  if (costs.size > 0) rows.push({ label: translations.sizeFee, value: costs.size });
  if (costs.distance > 0) rows.push({ label: translations.distanceFee, value: costs.distance });
  if (costs.weight > 0) rows.push({ label: translations.weightFee, value: costs.weight });
  if (costs.insurance > 0) rows.push({ label: translations.insuranceFee, value: costs.insurance });

  return (
    <div className="bg-gradient-to-br from-blue-50 to-blue-100 rounded-lg p-6 border border-blue-200">
      <h3 className="text-lg font-semibold text-blue-800 mb-4">
        {translations.totalCost}
      </h3>

      <div className="space-y-3">
        {rows.length === 0 && (
          <p className="text-sm text-gray-500">{translations.selectSize || '—'}</p>
        )}
        {rows.map((r) => (
          <div key={r.label} className="flex justify-between items-center">
            <span className="text-gray-700">{r.label}:</span>
            <span className="font-semibold text-gray-900">{formatCurrency(r.value, currency)}</span>
          </div>
        ))}

        {rows.length > 0 && (
          <div className="border-t border-blue-200 pt-3">
            <div className="flex justify-between items-center">
              <span className="text-lg font-bold text-blue-800">Total:</span>
              <span className="text-2xl font-bold text-blue-800">{formatCurrency(costs.total, currency)}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default CostSummary;
