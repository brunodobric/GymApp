// Paket klipova MoveKit za Google Play (install-time asset pack, docs/android-izdanje.md). Osnovni modul na Playu smije
// imati najviše oko 200 MB, a klipovi su veći, pa idu u ovaj paket. Play ga instalira zajedno s aplikacijom, a sadržaj
// se čita kao obični asseti (`assets/movekit/...`), pa kod ne zna gdje je.
//
// Sadržaj (src/main/assets/movekit/) priprema scripts/movekit-android.sh i nikad ne ide u repozitorij (docs/movekit.md).
// Modul se uključuje samo kad sadržaj postoji (settings.gradle.kts), pa build bez MoveKita radi kao prije.
plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName.set("movekit")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}
