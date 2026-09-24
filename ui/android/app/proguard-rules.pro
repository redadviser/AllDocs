# google_mlkit_text_recognition references the Chinese, Devanagari,
# Japanese and Korean recognizers, which only exist if their model
# dependencies are added. AllDocs only uses the Latin one
# (TextRecognitionScript.latin), so tell R8 the others are meant to be
# missing.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
