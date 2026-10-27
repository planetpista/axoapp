import React from 'react';
import { Mail, Package, Truck, Container } from 'lucide-react';
import { Category, ExportType } from '../utils/shippingConfig';

interface CategorySelectorProps {
  value: string;
  exportType: string;
  onChange: (category: Category | '') => void;
  onExportTypeChange: (t: ExportType) => void;
  translations: any;
}

const CATEGORY_DEFS = [
  { id: 'Mail', icon: Mail, key: 'mail' },
  { id: 'Parcel', icon: Package, key: 'parcel' },
  { id: 'Moving', icon: Truck, key: 'moving' },
  { id: 'Export', icon: Container, key: 'export' },
];

const EXPORT_DEFS: { id: ExportType; key: string }[] = [
  { id: 'Parcel', key: 'parcel' },
  { id: 'Air', key: 'air' },
  { id: 'Container', key: 'container' },
];

const CategorySelector: React.FC<CategorySelectorProps> = ({
  value,
  exportType,
  onChange,
  onExportTypeChange,
  translations,
}) => {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {CATEGORY_DEFS.map(({ id, icon: Icon, key }) => (
          <button
            key={id}
            type="button"
            onClick={() => onChange(id as Category)}
            className={`flex flex-col items-center p-4 rounded-lg border-2 transition-all duration-200 ${
              value === id
                ? 'border-blue-500 bg-blue-50 text-blue-700'
                : 'border-gray-200 bg-white text-gray-600 hover:border-blue-300 hover:bg-blue-50'
            }`}
          >
            <Icon size={28} className="mb-2" />
            <span className="font-medium text-sm">{translations[key]}</span>
          </button>
        ))}
      </div>

      {value === 'Export' && (
        <div className="grid grid-cols-3 gap-3 pt-2">
          {EXPORT_DEFS.map(({ id, key }) => (
            <button
              key={id}
              type="button"
              onClick={() => onExportTypeChange(id)}
              className={`flex items-center justify-center p-3 rounded-lg border-2 transition-all duration-200 ${
                exportType === id
                  ? 'border-blue-500 bg-blue-50 text-blue-700'
                  : 'border-gray-200 bg-white text-gray-600 hover:border-blue-300 hover:bg-blue-50'
              }`}
            >
              <span className="font-medium text-sm">
                {key === 'parcel' ? translations.parcel : key === 'air' ? translations.air || 'Avion' : translations.container}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default CategorySelector;
