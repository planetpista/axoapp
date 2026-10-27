export type Category = 'Mail' | 'Parcel' | 'Moving' | 'Export';
export type ExportType = 'Parcel' | 'Air' | 'Container';
export type Size = 'XS' | 'S' | 'M' | 'L' | 'XL';

export interface SizeOption {
  id: Size;
  volumeLabel?: string;
  vehicleLabel?: { en: string; fr: string };
  surcharge: number;
  weightMin?: number;
  weightMax?: number;
}

export interface CategoryMeta {
  id: Category;
  icon: string;
  hasSize: boolean;
  hasDistance: boolean;
  hasWeight: boolean;
  hasExportType: boolean;
}

export const CATEGORIES: CategoryMeta[] = [
  { id: 'Mail', icon: 'Mail', hasSize: false, hasDistance: false, hasWeight: true, hasExportType: false },
  { id: 'Parcel', icon: 'Package', hasSize: true, hasDistance: true, hasWeight: true, hasExportType: false },
  { id: 'Moving', icon: 'Truck', hasSize: true, hasDistance: true, hasWeight: false, hasExportType: false },
  { id: 'Export', icon: 'Container', hasSize: false, hasDistance: false, hasWeight: true, hasExportType: true },
];

export const PARCEL_SIZES: SizeOption[] = [
  { id: 'XS', vehicleLabel: { en: 'Bike / Motorcycle', fr: 'Vélo / Moto' }, surcharge: 1, weightMax: 1 },
  { id: 'S', vehicleLabel: { en: 'Bike / Motorcycle / Car', fr: 'Vélo / Moto / Voiture' }, surcharge: 2, weightMin: 1, weightMax: 5 },
  { id: 'M', vehicleLabel: { en: 'Car', fr: 'Voiture' }, surcharge: 4, weightMin: 5, weightMax: 10 },
  { id: 'L', vehicleLabel: { en: 'Van', fr: 'Van' }, surcharge: 6, weightMin: 10, weightMax: 20 },
  { id: 'XL', vehicleLabel: { en: 'Large Van', fr: 'Grand Van' }, surcharge: 10, weightMin: 20 },
];

export const MOVING_SIZES: SizeOption[] = [
  { id: 'XS', volumeLabel: '6 m³', surcharge: 0 },
  { id: 'S', volumeLabel: '9 m³', surcharge: 20 },
  { id: 'M', volumeLabel: '12 m³', surcharge: 40 },
  { id: 'L', volumeLabel: '20 m³', surcharge: 50 },
  { id: 'XL', volumeLabel: '20 m³ (Truck)', surcharge: 100 },
];

export const EXPORT_TYPES: { id: ExportType; label: { en: string; fr: string } }[] = [
  { id: 'Parcel', label: { en: 'Parcel', fr: 'Colis' } },
  { id: 'Air', label: { en: 'Air', fr: 'Avion' } },
  { id: 'Container', label: { en: 'Container', fr: 'Conteneur' } },
];

export const PRICING = {
  mail: { flatFee: 3 },
  parcel: { pickupFee: 2, perKm: 0.75 },
  moving: { baseFee: 49, perKm: 0.75 },
  export: { perKg: 9.99 },
};
