Name:       okboard-full
Summary:    OKboard (Jolla magic keyboard)
Version:    0.6.1
Release:    1
Group:      System/GUI/Other
License:    BSD-like + LGPLv2.1
URL:        http://projects.tuxfamily.org/?do=group;name=okboard
Source0:    okboard-%{version}.tar.gz
Source1:    okb-engine-%{version}.tar.gz
Source2:    okb-lang-fr.tar.bz2
Source3:    okb-lang-en.tar.bz2
Source4:    okb-lang-nl.tar.bz2
Requires:   pyotherside-qml-plugin-python3-qt5 >= 1.2.0
Requires:   jolla-keyboard >= 0.5.5
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Gui)
BuildRequires:  pkgconfig(sailfishapp) >= 0.0.10
BuildRequires:  desktop-file-utils
BuildRequires:  python3-devel
Provides:   okb-engine
Conflicts:  okb-engine


%define qml_subdir eu/cpbm/okboard
%define qml_maliit_dir /usr/share/maliit/plugins/%{qml_subdir}
%define share_dir /usr/share/okboard
%define plugin_dir /usr/lib/maliit/plugins
%define bin_dir /usr/bin

%description
OKboard maliit plugin and simple settings application.
This is a standalone package: it includes okb-engine library and language files for English, French & Dutch.

%prep
%setup -c -n okboard-full-%{_arch} -a 0 -a 1

%build
# engine
pushd okb-engine-%{version}
cp README.md README-engine.md
cp LICENSE LICENSE-engine

qmake
make -j 3
echo "%{version}-%{release} build: "`date` > engine.version

cd ngrams
CFLAGS="" python3 setup-fslm.py build_ext --inplace
CFLAGS="" python3 setup-cdb.py build_ext --inplace
mv cfslm*.so cfslm.so
mv cdb*.so cdb.so
popd

# keyboard
pushd okboard-%{version}
qmake
make
echo "%{version}-%{release} build: "`date` > okboard.version

cat version.cf | grep '^DB_VERSION' | cut -d'=' -f 2 | tr -cd '0-9' > db.version
cat version.cf | grep '^CF_VERSION' | cut -d'=' -f 2 | tr -cd '0-9' > cf.version

popd

%install
rm -rf %{buildroot}

# engine
pushd okb-engine-%{version}
cp README.md README-keyboard.md
cp LICENSE LICENSE-keyboard

mkdir -p %{buildroot}/%{qml_maliit_dir} %{buildroot}/%{share_dir}
cp -p curve/build/libcurveplugin.so %{buildroot}/%{qml_maliit_dir}
cp predict.py %{buildroot}/%{qml_maliit_dir}
cp language_model.py %{buildroot}/%{qml_maliit_dir}
cp backend.py %{buildroot}/%{qml_maliit_dir}
cp engine.version %{buildroot}/%{qml_maliit_dir}
cp okboard.cf %{buildroot}/%{share_dir}
cp -p ngrams/cfslm.so %{buildroot}/%{qml_maliit_dir}
cp -p ngrams/cdb.so %{buildroot}/%{qml_maliit_dir}

tar xvfj %{SOURCE2}
tar xvfj %{SOURCE3}
tar xvfj %{SOURCE4}

for lang in fr en nl ; do
    cat $lang.tre | gzip -c > %{buildroot}/%{share_dir}/$lang.tre.gz
    cat predict-$lang.db | gzip -c > %{buildroot}/%{share_dir}/predict-$lang.db.gz
    cat predict-$lang.ng | gzip -c > %{buildroot}/%{share_dir}/predict-$lang.ng.gz
    cp -f predict-$lang.id %{buildroot}/%{share_dir}/predict-$lang.id
done
popd

# keyboard
pushd okboard-%{version}
mkdir -p %{buildroot}/%{qml_maliit_dir} %{buildroot}/%{share_dir} %{buildroot}/%{plugin_dir} %{buildroot}/%{bin_dir}

ln -sf /usr/share/maliit/plugins/com/jolla/touchpointarray.js %{buildroot}/%{qml_maliit_dir}/touchpointarray.js

for file in CurveKeyboardBase.qml okboard.py Gribouille.qml PredictList.qml qmldir Settings.qml pen.png curves.js VerticalPredictList.qml ; do
    cp -f qml/%{qml_subdir}/$file %{buildroot}/%{qml_maliit_dir}/
done

patch -o %{buildroot}/%{share_dir}/okboard1.qml plugin/okboard.qml plugin/okboard_2to1.diff

cp plugin/okboard.qml %{buildroot}/%{share_dir}/
cp plugin/okboard_2to1.diff %{buildroot}/%{share_dir}/
cp plugin/install_plugin.sh %{buildroot}/%{share_dir}/

cp build/okboard-settings %{buildroot}/%{bin_dir}/

mkdir -p %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/icons/hicolor/86x86/apps
cp okboard.desktop %{buildroot}%{_datadir}/applications
cp okboard.png %{buildroot}%{_datadir}/icons/hicolor/86x86/apps

cp okboard.version %{buildroot}/%{qml_maliit_dir}
cp db.version %{buildroot}/%{qml_maliit_dir}
cp cf.version %{buildroot}/%{qml_maliit_dir}

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

popd

%post
rm -f /home/nemo/.config/maliit.org/server.conf
killall maliit-server 2>/dev/null || true
killall okboard-settings 2>/dev/null || true
%{share_dir}/install_plugin.sh %{plugin_dir}

%postun
rm -f /home/nemo/.config/maliit.org/server.conf
killall maliit-server 2>/dev/null || true
killall okboard-settings 2>/dev/null || true
rm -f %{plugin_dir}/okboard.qml

%files
%defattr(-,root,root,-)

# engine
%doc okb-engine-%{version}/README.md okb-engine-%{version}/LICENSE
%defattr(-,root,root,-)
%{qml_maliit_dir}/libcurveplugin.so
%{qml_maliit_dir}/predict.py*
%{qml_maliit_dir}/language_model.py*
%{qml_maliit_dir}/backend.py*
%{qml_maliit_dir}/cfslm.so
%{qml_maliit_dir}/cdb.so
%{qml_maliit_dir}/engine.version
%{share_dir}/okboard.cf

%{share_dir}/fr.tre.gz
%{share_dir}/predict-fr.db.gz
%{share_dir}/predict-fr.ng.gz
%{share_dir}/predict-fr.id

%{share_dir}/en.tre.gz
%{share_dir}/predict-en.db.gz
%{share_dir}/predict-en.ng.gz
%{share_dir}/predict-en.id

%{share_dir}/nl.tre.gz
%{share_dir}/predict-nl.db.gz
%{share_dir}/predict-nl.ng.gz
%{share_dir}/predict-nl.id

# keyboard
%doc okboard-%{version}/README.md okboard-%{version}/LICENSE
%{qml_maliit_dir}/CurveKeyboardBase.qml
%{qml_maliit_dir}/Gribouille.qml
%{qml_maliit_dir}/PredictList.qml
%{qml_maliit_dir}/touchpointarray.js
%{qml_maliit_dir}/qmldir
%{qml_maliit_dir}/okboard.py*
%{qml_maliit_dir}/Settings.qml
%{qml_maliit_dir}/okboard.version
%{qml_maliit_dir}/db.version
%{qml_maliit_dir}/cf.version
%{qml_maliit_dir}/pen.png
%{qml_maliit_dir}/curves.js
%{qml_maliit_dir}/VerticalPredictList.qml
%{share_dir}/okboard.qml
%{share_dir}/okboard_2to1.diff
%{share_dir}/okboard1.qml
%{share_dir}/install_plugin.sh
%{bin_dir}/okboard-settings
%{_datadir}/applications/okboard.desktop
%{_datadir}/icons/hicolor/86x86/apps/okboard.png

