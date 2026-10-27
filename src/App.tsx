import React, { useState } from 'react';
import { Truck } from 'lucide-react';
import LanguageToggle from './components/LanguageToggle';
import MenuButton from './components/MenuButton';
import Menu from './components/Menu';
import SettingsPage from './components/SettingsPage';
import ContactPage from './components/ContactPage';
import PayPalButton from './components/PayPalButton';
import AdminDashboard from './components/admin/AdminDashboard';
import FormSection from './components/FormSection';
import CategorySelector from './components/CategorySelector';
import PersonInfoForm from './components/PersonInfoForm';
import CostSummary from './components/CostSummary';
import { ShippingData, Currency } from './types';
import { translations } from './utils/translations';
import { currencies } from './utils/currencies';
import {
  Category,
  ExportType,
  Size,
  PARCEL_SIZES,
  MOVING_SIZES,
} from './utils/shippingConfig';
import { useShippingCalculator } from './hooks/useShippingCalculator';
import { useRouteCalculation } from './hooks/useRouteCalculation';
import { sendShippingConfirmation } from './services/emailService';
import DriverMapPage from './components/DriverMapPage';

function App() {
  const [language, setLanguage] = useState<'en' | 'fr'>('fr');
  const [currentPage, setCurrentPage] = useState<'home' | 'settings' | 'contact' | 'admin' | 'drivermap'>('home');
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [currentCurrency, setCurrentCurrency] = useState<Currency>(currencies[0]);
  const [showPayment, setShowPayment] = useState(false);
  const [paymentStatus, setPaymentStatus] = useState<'idle' | 'processing' | 'success' | 'error'>('idle');
  const [userRole, setUserRole] = useState<'admin' | 'courier' | 'client'>('client');
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [currentUser, setCurrentUser] = useState<any>(null);
  const [shippingData, setShippingData] = useState<ShippingData>({
    category: '',
    exportType: '',
    size: '',
    distance: 0,
    details: '',
    country: '',
    weight: 0,
    sender: { address: '', firstName: '', lastName: '', contact: '', email: '', country: '' },
    recipient: { address: '', firstName: '', lastName: '', contact: '', email: '', country: '' },
    insurance: false,
    message: '',
  });

  const costs = useShippingCalculator(shippingData, currentCurrency);

  const routeEnabled = shippingData.category === 'Parcel' || shippingData.category === 'Moving';
  const routeState = useRouteCalculation({
    pickupAddress: shippingData.sender.address,
    dropoffAddress: shippingData.recipient.address,
    enabled: routeEnabled,
  });

  const autoDistanceRounded = routeState.distanceKm > 0 ? Math.round(routeState.distanceKm * 10) / 10 : 0;
  const effectiveDistance = autoDistanceRounded || shippingData.distance;
  const liveDistance = effectiveDistance;
  const liveCost = useShippingCalculator(
    { ...shippingData, distance: liveDistance },
    currentCurrency
  );

  const t = (key: string) => translations[key]?.[language] || key;
  const countries = ['Benin', 'China', 'France'];

  const updateShippingData = (updates: Partial<ShippingData>) => {
    setShippingData((prev) => ({ ...prev, ...updates }));
  };

  const handleCategoryChange = (category: Category | '') => {
    setShippingData((prev) => ({
      ...prev,
      category,
      exportType: category === 'Export' ? prev.exportType : '',
      size: '',
      distance: 0,
      weight: category === 'Moving' ? 0 : prev.weight,
    }));
  };

  const handlePaymentSuccess = async (details: any) => {
    setPaymentStatus('success');
    try {
      await sendShippingConfirmation(shippingData, costs.total, currentCurrency, details);
    } catch (error) {
      console.error('Failed to send confirmation email:', error);
    }
    setTimeout(() => {
      setShowPayment(false);
      setPaymentStatus('idle');
    }, 3000);
  };

  const handlePaymentError = (error: any) => {
    console.error('Payment failed:', error);
    setPaymentStatus('error');
    setTimeout(() => setPaymentStatus('idle'), 3000);
  };

  const handleShipSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setShowPayment(true);
  };

  const handleAdminLogin = () => {
    setUserRole('admin');
    setIsLoggedIn(true);
    setCurrentPage('admin');
  };

  const handleLogout = () => {
    setUserRole('client');
    setIsLoggedIn(false);
    setCurrentUser(null);
    setCurrentPage('home');
  };

  const handleAuthSuccess = (user: any) => {
    setCurrentUser(user);
    setIsLoggedIn(true);
    if (user.profile) {
      setUserRole(user.profile.role);
      if (user.profile.role === 'admin') setCurrentPage('admin');
    }
  };

  if (currentPage === 'admin') {
    return <AdminDashboard onLogout={handleLogout} userRole={userRole} />;
  }
  if (currentPage === 'settings') {
    return (
      <SettingsPage
        onBack={() => setCurrentPage('home')}
        currentCurrency={currentCurrency}
        onCurrencyChange={setCurrentCurrency}
        translations={{ settings: t('settings'), currency: t('currency'), selectCurrency: t('selectCurrency') }}
      />
    );
  }
  if (currentPage === 'contact') {
    return (
      <ContactPage
        onBack={() => setCurrentPage('home')}
        translations={{
          contactUs: t('contactUs'),
          emailAddress: t('emailAddress'),
          phoneNumber: t('phoneNumber'),
          easySimpleFast: t('easySimpleFast'),
        }}
      />
    );
  }
  if (currentPage === 'drivermap') {
    return <DriverMapPage onBack={() => setCurrentPage('home')} language={language} currency={currentCurrency} />;
  }

  const sizeOptions = shippingData.category === 'Parcel' ? PARCEL_SIZES : MOVING_SIZES;
  const showWeight = shippingData.category === 'Mail' || shippingData.category === 'Parcel' || shippingData.category === 'Export';
  const showDistance = shippingData.category === 'Parcel' || shippingData.category === 'Moving';
  const showSize = shippingData.category === 'Parcel' || shippingData.category === 'Moving';

  return (
    <div className="min-h-screen bg-gray-50">
      <Menu
        isOpen={isMenuOpen}
        onClose={() => setIsMenuOpen(false)}
        onNavigate={setCurrentPage}
        currentPage={currentPage}
        onAuthSuccess={handleAuthSuccess}
        translations={{ home: t('home'), settings: t('settings'), contact: t('contact'), driverMap: t('driverMap'), signIn: 'Sign in / up' }}
      />

      <div className="flex justify-between items-center p-6">
        <div className="flex items-center gap-3">
          <LanguageToggle currentLanguage={language} onLanguageChange={setLanguage} />
          <h1 className="text-2xl font-bold text-blue-800">Axoxia</h1>
        </div>
        <div className="flex items-center gap-3">
          <MenuButton onClick={() => setIsMenuOpen(true)} translations={{ menu: t('menu') }} />
        </div>
      </div>

      <div className="text-center py-8 mb-8">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-800 mb-4">{t('easySimpleFast')}</h2>
      </div>

      <div className="max-w-4xl mx-auto px-6 pb-12">
        <form className="space-y-8" onSubmit={handleShipSubmit}>
          <FormSection title={t('category')}>
            <CategorySelector
              value={shippingData.category}
              exportType={shippingData.exportType}
              onChange={handleCategoryChange}
              onExportTypeChange={(et: ExportType) => updateShippingData({ exportType: et })}
              translations={{
                mail: t('mail'),
                parcel: t('parcel'),
                moving: t('moving'),
                export: t('export'),
                container: t('container'),
                air: t('air'),
              }}
            />
          </FormSection>

          {showSize && (
            <FormSection title={t('size')}>
              <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                {sizeOptions.map((s) => (
                  <button
                    key={s.id}
                    type="button"
                    onClick={() => updateShippingData({ size: s.id as Size })}
                    className={`flex flex-col items-center p-3 rounded-lg border-2 transition-all duration-200 ${
                      shippingData.size === s.id
                        ? 'border-blue-500 bg-blue-50 text-blue-700'
                        : 'border-gray-200 bg-white text-gray-600 hover:border-blue-300'
                    }`}
                  >
                    <span className="font-bold mb-1">{s.id}</span>
                    <span className="text-xs text-center">
                      {s.volumeLabel ?? s.vehicleLabel?.[language]}
                    </span>
                    {s.surcharge > 0 && (
                      <span className="text-xs text-gray-500 mt-1">+{s.surcharge} €</span>
                    )}
                  </button>
                ))}
              </div>
            </FormSection>
          )}

          {showDistance && (
            <FormSection title={t('distance')}>
              <div className="space-y-3">
                <div>
                  <input
                    type="number"
                    value={shippingData.distance || ''}
                    onChange={(e) => updateShippingData({ distance: parseFloat(e.target.value) || 0 })}
                    placeholder={t('distancePlaceholder') || '0'}
                    min="0"
                    step="1"
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200"
                  />
                  <p className="text-xs text-gray-500 mt-1">{t('distanceManualHint')}</p>
                </div>
                {routeEnabled && (
                  <div className="flex items-center gap-2 text-sm">
                    {routeState.loading ? (
                      <span className="text-blue-600">{t('calculatingRoute')}</span>
                    ) : routeState.error ? (
                      <span className="text-red-600">{t('routeError')}</span>
                    ) : routeState.distanceKm > 0 ? (
                      <span className="text-green-700 font-medium">
                        {t('autoDistance')}: {autoDistanceRounded} km
                      </span>
                    ) : (
                      <span className="text-gray-500">{t('autoDistanceHint')}</span>
                    )}
                  </div>
                )}
              </div>
            </FormSection>
          )}

          {showWeight && (
            <FormSection title={t('weight')}>
              <input
                type="number"
                value={shippingData.weight || ''}
                onChange={(e) => updateShippingData({ weight: parseFloat(e.target.value) || 0 })}
                placeholder="0"
                min="0"
                step="0.1"
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200"
              />
            </FormSection>
          )}

          <FormSection title={t('details')}>
            <textarea
              value={shippingData.details}
              onChange={(e) => updateShippingData({ details: e.target.value })}
              placeholder={t('detailsPlaceholder')}
              rows={3}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200 resize-none"
            />
          </FormSection>

          <FormSection title={t('sender')}>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">{t('country')}</label>
              <select
                value={shippingData.sender.country || ''}
                onChange={(e) => updateShippingData({ sender: { ...shippingData.sender, country: e.target.value } })}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200"
              >
                <option value="">{t('selectCountry')}</option>
                {countries.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
            </div>
            <PersonInfoForm
              data={shippingData.sender}
              onChange={(sender) => updateShippingData({ sender })}
              translations={{
                address: t('address'),
                firstName: t('firstName'),
                lastName: t('lastName'),
                contact: t('contact'),
                email: t('email'),
                addressPlaceholder: t('addressPlaceholder'),
                firstNamePlaceholder: t('firstNamePlaceholder'),
                lastNamePlaceholder: t('lastNamePlaceholder'),
                contactPlaceholder: t('contactPlaceholder'),
                emailPlaceholder: t('emailPlaceholder'),
              }}
            />
          </FormSection>

          <FormSection title={t('recipient')}>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">{t('country')}</label>
              <select
                value={shippingData.recipient.country || ''}
                onChange={(e) => updateShippingData({ recipient: { ...shippingData.recipient, country: e.target.value } })}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200"
              >
                <option value="">{t('selectCountry')}</option>
                {countries.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
            </div>
            <PersonInfoForm
              data={shippingData.recipient}
              onChange={(recipient) => updateShippingData({ recipient })}
              translations={{
                address: t('address'),
                firstName: t('firstName'),
                lastName: t('lastName'),
                contact: t('contact'),
                email: t('email'),
                addressPlaceholder: t('addressPlaceholder'),
                firstNamePlaceholder: t('firstNamePlaceholder'),
                lastNamePlaceholder: t('lastNamePlaceholder'),
                contactPlaceholder: t('contactPlaceholder'),
                emailPlaceholder: t('emailPlaceholder'),
              }}
            />
          </FormSection>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <FormSection title={t('insurance')}>
              <p className="text-sm text-gray-600 mb-4">{t('insuranceDescription')}</p>
              <div className="flex gap-4">
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="insurance"
                    checked={shippingData.insurance === true}
                    onChange={() => updateShippingData({ insurance: true })}
                    className="mr-2 text-blue-600 focus:ring-blue-500"
                  />
                  <span className="text-gray-700">{t('yes')}</span>
                </label>
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="insurance"
                    checked={shippingData.insurance === false}
                    onChange={() => updateShippingData({ insurance: false })}
                    className="mr-2 text-blue-600 focus:ring-blue-500"
                  />
                  <span className="text-gray-700">{t('no')}</span>
                </label>
              </div>
            </FormSection>

            <FormSection title={t('message')}>
              <textarea
                value={shippingData.message}
                onChange={(e) => updateShippingData({ message: e.target.value })}
                placeholder={t('messagePlaceholder')}
                rows={4}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-colors duration-200 resize-none"
              />
            </FormSection>
          </div>

          <CostSummary
            costs={liveCost}
            currency={currentCurrency}
            translations={{
              totalCost: t('totalCost'),
              shipping: t('shipping'),
              insuranceFee: t('insuranceFee'),
              baseFee: t('baseFee'),
              pickupFee: t('pickupFee'),
              sizeFee: t('sizeFee'),
              distanceFee: t('distanceFee'),
              weightFee: t('weightFee'),
              selectSize: t('selectSize'),
            }}
          />

          {!showPayment ? (
            <div className="flex justify-center pt-8">
              <button
                type="submit"
                disabled={liveCost.total === 0}
                className="flex items-center gap-3 px-12 py-4 bg-blue-600 text-white font-bold text-lg rounded-lg hover:bg-blue-700 transform hover:scale-105 transition-all duration-200 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
              >
                <Truck size={24} />
                {t('ship')}
              </button>
            </div>
          ) : (
            <div className="bg-white rounded-lg border border-gray-200 p-6 shadow-sm">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">{t('payNow')}</h3>
              {paymentStatus === 'success' && (
                <div className="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg">
                  <p className="text-green-800 font-medium">{t('paymentSuccess')}</p>
                </div>
              )}
              {paymentStatus === 'error' && (
                <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg">
                  <p className="text-red-800 font-medium">{t('paymentError')}</p>
                </div>
              )}
              <PayPalButton
                amount={liveCost.total}
                currency={currentCurrency}
                onSuccess={handlePaymentSuccess}
                onError={handlePaymentError}
                disabled={paymentStatus === 'processing'}
              />
              <button
                type="button"
                onClick={() => setShowPayment(false)}
                className="mt-4 w-full px-4 py-2 text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors duration-200"
              >
                Cancel
              </button>
            </div>
          )}
        </form>
      </div>
    </div>
  );
}

export default App;
