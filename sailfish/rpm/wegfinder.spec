Name:       wegfinder

Summary:    wegfinder: Routen, Abfahrten, Verkehrsmittel in der Nähe (inoffiziell)
Version:    0.1.1
Release:    1
License:    GPLv3
URL:        https://github.com/smatkovi/wegfinder
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtdeclarative-import-positioning
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  desktop-file-utils

%description
Inoffizieller Client für wegfinder: Routen in Österreich mit Öffis, Rad,
Auto, Sharing und Taxi, Abfahrten mit Echtzeit und Verkehrsmittel in der
Nähe auf einer eigenen OpenStreetMap-Karte. Ohne Buchen und Bezahlen,
ohne Konto. Nicht von der iMobility GmbH.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5 wegfinder.pro VERSION=%{version}
%make_build

%install
%qmake5_install
# Der Netzdienst ist ein statisches Rust-Binary, gebaut von
# tools/build-dienst.sh fuer genau diese Architektur.
install -D -m 755 prebuilt/%{_target_cpu}/wf-dienst %{buildroot}/usr/libexec/wegfinder/wf-dienst
desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
  %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
/usr/libexec/wegfinder

%changelog
* Thu Oct 15 2026 Sebastian Matkovich <sebastian.matkovich@gmail.com> - 0.1.1-1
- Sailfish: im Sailjail-Sandkasten (Internet, Standort, Downloads) statt
  ohne; Daten unter org.smatkovi/wegfinder.

* Thu Oct 15 2026 Sebastian Matkovich <sebastian.matkovich@gmail.com> - 0.1.0-1
- Erste Fassung: Routen (Öffis, Rad, Auto, Sharing, Taxi), Abfahrten mit
  Echtzeit, Fahrtverlauf, Verkehrsmittel in der Nähe, eigene Karte mit
  Kachel-Zwischenspeicher, Favoriten und Verlauf. Ohne Buchen und Bezahlen.
