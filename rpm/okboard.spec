Name:       okboard
Summary:    OKboard (Jolla magic keyboard)
Version:    0.4.9
Release:    1
Group:      System/GUI/Other
License:    BSD-like
URL:        file:///dev/null
Source0:    %{name}-%{version}.tar.gz
Requires:   pyotherside-qml-plugin-python3-qt5 >= 1.2.0
Requires:   jolla-keyboard >= 0.4.23.2
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Gui)
BuildRequires:  pkgconfig(sailfishapp) >= 0.0.10
BuildRequires:  desktop-file-utils

%define qml_subdir eu/cpbm/okboard
%define qml_maliit_dir /usr/share/maliit/plugins/%{qml_subdir}
%define share_dir /usr/share/okboard
%define plugin_dir /usr/lib/maliit/plugins
%define bin_dir /usr/bin

%description
OKboard maliit plugin and simple settings application

%prep
%setup -n %{name}-%{version}

%build
qmake
make
echo "%{version}-%{release} build: "`date` > okboard.version

cat version.cf | grep '^DB_VERSION' | cut -d'=' -f 2 | tr -cd '0-9' > db.version

%install
rm -rf %{buildroot}

mkdir -p %{buildroot}/%{qml_maliit_dir} %{buildroot}/%{share_dir} %{buildroot}/%{plugin_dir} %{buildroot}/%{bin_dir}

ln -sf /usr/share/maliit/plugins/com/jolla/touchpointarray.js %{buildroot}/%{qml_maliit_dir}/touchpointarray.js 

for file in CurveKeyboardBase.qml okboard.py Gribouille.qml PredictList.qml qmldir Settings.qml pen.png ; do
    cp -f qml/%{qml_subdir}/$file %{buildroot}/%{qml_maliit_dir}/
done

cp plugin/okboard.qml %{buildroot}/%{plugin_dir}/

cp build/okboard-settings %{buildroot}/%{bin_dir}/

mkdir -p %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/icons/hicolor/86x86/apps
cp okboard.desktop %{buildroot}%{_datadir}/applications
cp okboard.png %{buildroot}%{_datadir}/icons/hicolor/86x86/apps

cp okboard.version %{buildroot}/%{qml_maliit_dir}
cp db.version %{buildroot}/%{qml_maliit_dir}

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%post
rm -f /home/nemo/.config/maliit.org/server.conf
killall maliit-server 2>/dev/null || true
killall okboard-settings 2>/dev/null || true

%postun
rm -f /home/nemo/.config/maliit.org/server.conf
killall maliit-server 2>&1 || true
killall okboard-settings 2>/dev/null || true

%files
%defattr(-,root,root,-)
%doc README.md LICENSE
%{qml_maliit_dir}/CurveKeyboardBase.qml
%{qml_maliit_dir}/Gribouille.qml
%{qml_maliit_dir}/PredictList.qml
%{qml_maliit_dir}/touchpointarray.js
%{qml_maliit_dir}/qmldir
%{qml_maliit_dir}/okboard.py*
%{qml_maliit_dir}/Settings.qml
%{qml_maliit_dir}/okboard.version
%{qml_maliit_dir}/db.version
%{qml_maliit_dir}/pen.png
%{plugin_dir}/okboard.qml
%{bin_dir}/okboard-settings
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/86x86/apps/%{name}.png

