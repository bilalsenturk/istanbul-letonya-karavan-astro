# iOS Navigasyon Sadelestirme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** KUZEY ana ekranlarinin ustundeki ozel cubugu kaldirip hesap ve yolculuk islemlerini sistem navigasyonuna tasimak.

**Architecture:** `ContentView` yalnizca ana yuzey secimini ve `TabView` yapisini yonetecek. Yeniden kullanilabilir `JourneyMenuView`, oturum ve secili yolculuk durumuna gore giris, rotalar, uyeler ve hesap islemlerini sunacak; Panel ve Araclar bu yuzeyi sheet olarak acacak.

**Tech Stack:** SwiftUI, mevcut `AccountSessionStore`, `TripWorkspaceStore`, XCTest yerine mevcut Swift kontrol betikleri ve Simulator `xcodebuild` dogrulamasi.

## Global Constraints

- Ozel ust yolculuk cubugu olmayacak.
- Ana yuzey Panel, Duraklar, Plan, Gunluk ve Araclar sistem sekmelerini koruyacak.
- Hesap, rota degistirme ve uye yonetimi erisilebilir kalacak.
- iPhone ve iPad yerlesimleri Simulator ekran goruntuleriyle dogrulanacak.
- Mevcut ilgisiz calisma agaci degisiklikleri korunacak.

---

### Task 1: Ana uygulama kabugunu sadelestir

**Files:**
- Modify: `ios/Karavan/Views/ContentView.swift`
- Test: `ios/Tests/account-domain-check.swift`

**Interfaces:**
- Consumes: `AccountSessionStore.isSignedIn`, `TripWorkspaceStore.selectedTrip`, `AppNavigation.selectedTab`
- Produces: ust cubuksuz `kuzeyTabs`

- [ ] **Step 1:** Mevcut hesap alan kontrolunu calistir ve temel davranisi kaydet.
- [ ] **Step 2:** `guestTripBar`, `selectedTripBar` ve bunlara ait sheet durumlarini `ContentView` icinden kaldir.
- [ ] **Step 3:** Misafir ve KUZEY durumlarinda dogrudan `kuzeyTabs` dondur.
- [ ] **Step 4:** Hesap alan kontrolunu yeniden calistir.

### Task 2: Hesap ve yolculuk yuzeyi ekle

**Files:**
- Create: `ios/Karavan/Views/Trips/JourneyMenuView.swift`
- Modify: `ios/Karavan/Views/DashboardView.swift`
- Modify: `ios/Karavan/Views/Tools/ToolsView.swift`

**Interfaces:**
- Consumes: `AccountSessionStore`, `TripWorkspaceStore`, mevcut `SignInView`, `MembersView`, `AccountMenuView`
- Produces: `JourneyMenuView`, Panel profil butonu ve Araclar yolculuk satiri

- [ ] **Step 1:** Misafir durumda Apple ile giris, oturum acmis durumda rota/uye/hesap eylemlerini gosteren `JourneyMenuView` yaz.
- [ ] **Step 2:** Panel sistem toolbar'ina tek profil simgesi ve sheet sunumu ekle.
- [ ] **Step 3:** Araclar ekraninin ilk bolumune `Hesap ve yolculuk` satiri ve ayni sheet sunumunu ekle.
- [ ] **Step 4:** Rotalarim eyleminde sheet'i kapatip `workspace.closeTrip()` ile `TripsHomeView` yuzeyine gec.

### Task 3: Derleme ve gorsel dogrulama

**Files:**
- Verify: `ios/Kuzey.xcodeproj`

**Interfaces:**
- Consumes: tamamlanan SwiftUI degisiklikleri
- Produces: iPhone ve iPad ekran goruntuleri ile dogrulanmis uygulama

- [ ] **Step 1:** Tum mevcut iOS kontrol betiklerini calistir.
- [ ] **Step 2:** `xcodebuild` ile imzasiz Simulator derlemesi al.
- [ ] **Step 3:** iPhone 17 ve iPad (A16) cihazlarina kurup uygulamayi ac.
- [ ] **Step 4:** Panel ve Araclar ekranlarinda ust cubugun kalktigini, sekmelerin gorundugunu ve hesap girislerinin calistigini ekran goruntuleriyle kontrol et.
- [ ] **Step 5:** `git diff --check` calistir ve yalnizca ilgili degisiklikleri raporla.
