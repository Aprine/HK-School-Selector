# HK School Selector 🏫

An intelligent school discovery ecosystem built with **Flutter**, designed to help users efficiently find schools in Hong Kong by integrating official EDB data, geospatial services, and LLM-powered AI assistance.

---

## 🌟 Key Features

### 🔍 Smart Discovery & Search
* **Official Data Integration:** Fetches real-time school information via the Education Bureau (EDB) API.
* **Advanced Filtering:** Supports searching by school name, filtering by district/type, and custom sorting.
* **Robust UI:** Implements pull-to-refresh and comprehensive error handling with fallback states to ensure a smooth user experience.
* **Detailed Insights:** Comprehensive school detail pages including address, contact info, website, and category.

### 📍 Geospatial Intelligence
* **One-Click Navigation:** Seamless integration with **Google Maps** for instant directions.
* **Nearby Recommendations:** Uses real-time geolocation to recommend the closest schools based on the user's current position.
* **District Analytics:** Displays rankings of school distributions across different districts.

### ❤️ Personalization & Security
* **Favorites System:** Heart-button functionality with local persistence for quick access to saved schools.
* **User Isolation:** Local account system ensuring that favorite lists are isolated per user.

### 🤖 AI Chat Assistant
* **Natural Language Querying:** Users can filter schools or ask questions using natural language (e.g., *"Find me primary schools in Tai Po"*).
* **Controlled Intelligence:** Implements a "Local-First" retrieval strategy to provide factual school data to the LLM, significantly reducing hallucinations.

---

## 🛠 Technical Architecture

### Frontend (Flutter)
* **Architecture:** Modular structure divided into `models`, `services`, and `screens`.
* **Data Layer (`ApiService`):** Handles multi-source requests with built-in timeout management, caching, and data deduplication.
* **Local Storage:** Utilizes `SharedPreferences` for user accounts, favorites, and API cache.
* **Location Services:** Powered by the `Geolocator` package.

### Backend & AI (Node.js + LLM)
* **Proxy Server:** A **Node.js + Express** backend deployed on **Render**.
* **Security:** All sensitive API keys are managed via server-side environment variables to prevent frontend leakage.
* **AI Engine:** Integrated with the **Qwen (Tongyi Qianwen)** model via `AiAssistantService`.

---

## 🚀 Engineering Highlights

* **High Availability:** Implemented a **Multi-source Fallback + Cache** mechanism to ensure the app remains functional even during API downtime.
* **Data Integrity:** Developed a normalization pipeline using composite keys to eliminate duplicate school entries.
* **AI Optimization:** 
    * **Token Efficiency:** Implemented history truncation and concise response strategies to reduce token consumption.
    * **Accuracy:** Prioritizes local data injection over general model knowledge to ensure factual accuracy regarding school locations and distances.
* **Search Enhancement:** Integrated fuzzy matching to improve the recognition of school names despite minor typos.

---

## 📈 Project Impact
This project is more than a simple CRUD application; it represents a complete engineering lifecycle: **Development $\rightarrow$ Optimization $\rightarrow$ Deployment $\rightarrow$ Security**. It balances high-end user experience (UX) with industrial-grade stability and controlled AI integration.

---
## ⚙️ How to Run

1. **Clone the repository**
   ```bash
   git clone https://github.com/Aprine/HK-School-Selector.git
   cd HK-School-Selector

2. **Install Flutter dependencies**
   ```bash
   flutter pub get

3. **Start the Backend Server**
   ```bash
   npm install
   npm start

4. **Run the Application**
   ```bash
   flutter run
