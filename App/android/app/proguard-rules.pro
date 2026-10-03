# OsmAnd writes ALatLon into the AppInfo Bundle using its original class name.
# The peer APK cannot know our R8 name; retain the class and Parcelable factory.
# Keep the rule narrow: other AIDL and app code can still be optimized.
-keep,allowoptimization class net.osmand.aidlapi.map.ALatLon {
    public static final android.os.Parcelable$Creator CREATOR;
}
