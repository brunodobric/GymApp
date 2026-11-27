# R8 za release build (docs/android-izdanje.md).
#
# Bez preimenovanja: nazivi enuma (Enum.name, valueOf) i tipova zapisa spremaju se u bazu, sigurnosnu kopiju i poruke
# između mobitela i sata, pa moraju ostati isti kao u debug buildu i na iOS-u. Uz to stack trace u dijagnostici
# (ApplicationExitInfo) ostaje čitljiv bez mapping datoteke. R8 i dalje uklanja nekorišteni kod i resurse.
-dontobfuscate
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# Konstante enuma čitaju se po nazivu iz spremljenog teksta.
-keepclassmembers enum com.brunodobric.gymapp.** {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
