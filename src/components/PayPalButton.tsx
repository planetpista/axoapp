import React from 'react';
import { PayPalButtons, PayPalScriptProvider } from '@paypal/react-paypal-js';
import { Currency } from '../types';

interface PayPalButtonProps {
  amount: number;
  currency: Currency;
  onSuccess: (details: any) => void;
  onError: (error: any) => void;
  disabled?: boolean;
}

const PayPalButton: React.FC<PayPalButtonProps> = ({ 
  amount, 
  currency, 
  onSuccess, 
  onError, 
  disabled = false 
}) => {
  const paypalOptions = {
    "client-id": import.meta.env.VITE_PAYPAL_CLIENT_ID || "test",
    currency: currency.code === 'XOF' ? 'EUR' : currency.code, // PayPal doesn't support XOF directly
    intent: "capture"
  };

  // Convert XOF to EUR for PayPal if needed
  const paypalAmount = currency.code === 'XOF' ? (amount / currency.rate).toFixed(2) : amount.toFixed(2);
  const paypalCurrency = currency.code === 'XOF' ? 'EUR' : currency.code;

  return (
    <PayPalScriptProvider options={paypalOptions}>
      <PayPalButtons
        disabled={disabled}
        style={{
          layout: "vertical",
          color: "purple",
          shape: "rect",
          label: "paypal"
        }}
        createOrder={(data, actions) => {
          return actions.order.create({
            purchase_units: [{
              amount: {
                currency_code: paypalCurrency,
                value: paypalAmount
              },
              description: "Axoxia Shipping Service"
            }]
          });
        }}
        onApprove={async (data, actions) => {
          try {
            const details = await actions.order?.capture();

            // Verify the payment server-side using the PayPal secret
            const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
            const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
            if (supabaseUrl && supabaseAnonKey && details?.id) {
              try {
                const verifyRes = await fetch(`${supabaseUrl}/functions/v1/paypal-verify`, {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${supabaseAnonKey}`,
                  },
                  body: JSON.stringify({ orderID: details.id }),
                });
                if (!verifyRes.ok) {
                  onError(new Error("Server-side verification failed"));
                  return;
                }
                const verified = await verifyRes.json();
                if (!verified.verified || verified.status !== "COMPLETED") {
                  onError(new Error("Payment not completed"));
                  return;
                }
              } catch (verifyErr) {
                onError(verifyErr);
                return;
              }
            }

            onSuccess(details);
          } catch (error) {
            onError(error);
          }
        }}
        onError={onError}
      />
    </PayPalScriptProvider>
  );
};

export default PayPalButton;