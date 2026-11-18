# Solar Planner & Calculator

Rooftop solar estimator for Android (Capacitor) with USC number search and PDF quotes.

## Features
- System size, panel count and roof area from monthly units or monthly bill
- Project cost, PM Surya Ghar subsidy (residential), net cost
- Savings, payback, 25-year cumulative chart, CO2 avoided
- USC number field: validates format, searches saved estimates, auto-fills customer and consumption; buttons open the TGSPDCL / TGNPDCL sites to check a bill
- Save estimates on device, search by USC / name / phone / address, CSV export
- One-page PDF quote with your company name and phone (gear icon), shared via the Android share sheet

## Build the APK
Push to `main`, open GitHub > Actions > "Build Android APK", and download the `SolarPlannerCalculator-debug-apk` artifact.

## Local development
```
npm test        # calculation + PDF writer tests
npm start       # preview at http://localhost:5173
npm run build   # creates dist/
```

Defaults (yield 4 kWh/kW/day, Rs 60,000/kW, Rs 7.5/unit, subsidy Rs 30,000/kW up to 2 kW + Rs 18,000 for the 3rd kW) are editable under "Advanced assumptions".
