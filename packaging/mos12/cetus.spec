Name:           Cetus
Version:        1.0
Release:        1%{?dist}
Summary:        CNC Machine Control Application
Group:          Applications/Engineering
License:        GPL

# The tarball is produced by the repo helper script.
Source0:        %{name}-%{version}.tar.gz

%description
CNC Machine Control Application built with Qt/QML.

%prep
%setup -q

%build
mkdir -p build
cd build
QMAKE=qmake-qt5
command -v "$QMAKE" >/dev/null 2>&1 || QMAKE=qmake
"$QMAKE" "DEFINES+=CETUS_NO_LINGUIST" ..
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_datadir}/applications
mkdir -p %{buildroot}%{_datadir}/pixmaps
mkdir -p %{buildroot}%{_datadir}/qt5/translations

install -m 755 build/Cetus %{buildroot}%{_bindir}/Cetus

# Ship prebuilt translations (avoids needing lupdate/lrelease during build)
if ls -1 Cetus/translations/*.qm >/dev/null 2>&1; then
	install -m 644 Cetus/translations/*.qm %{buildroot}%{_datadir}/qt5/translations/
fi

cat > %{buildroot}%{_datadir}/applications/Cetus.desktop << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Cetus
Comment=CNC Machine Control Application
Exec=Cetus
Icon=Cetus
Categories=Utility;
Terminal=false
DESKTOP_EOF

cat > %{buildroot}%{_datadir}/pixmaps/Cetus.svg << ICON_EOF
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">
<rect width="256" height="256" fill="#4a90e2"/>
<text x="128" y="140" font-size="120" text-anchor="middle" fill="white">C</text>
</svg>
ICON_EOF

%files
%{_bindir}/Cetus
%{_datadir}/applications/Cetus.desktop
%{_datadir}/pixmaps/Cetus.svg
%{_datadir}/qt5/translations/cetus_*.qm

%changelog
* Tue Dec 23 2025 Packager <packager@local> - 1.0-1
- Initial package
