export interface ShippingData {
  category: 'Mail' | 'Parcel' | 'Moving' | 'Export' | '';
  exportType: 'Parcel' | 'Air' | 'Container' | '';
  size: 'XS' | 'S' | 'M' | 'L' | 'XL' | '';
  distance: number;
  details: string;
  country: 'Benin' | 'China' | 'France' | '';
  weight: number;
  sender: {
    address: string;
    firstName: string;
    lastName: string;
    contact: string;
    email: string;
    country: string;
  };
  recipient: {
    address: string;
    firstName: string;
    lastName: string;
    contact: string;
    email: string;
    country: string;
  };
  insurance: boolean;
  message: string;
}

export interface Language {
  code: 'en' | 'fr';
  label: string;
}

export interface Translations {
  [key: string]: {
    en: string;
    fr: string;
  };
}

export interface Currency {
  code: 'EUR' | 'XOF' | 'CNY';
  symbol: string;
  name: string;
  rate: number; // Rate relative to EUR
}

export interface PaymentData {
  amount: number;
  currency: string;
  description: string;
}