package com.example.verbix;

import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Bundle;

import androidx.appcompat.app.AppCompatActivity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.provider.MediaStore;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.SpannableStringBuilder;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;
import android.text.style.UnderlineSpan;
import android.util.Log;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import android.text.style.StyleSpan;
import android.text.style.RelativeSizeSpan;
import android.graphics.Typeface;
import java.util.function.Function;
import android.animation.ObjectAnimator;
import android.view.View;import android.graphics.Matrix;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.drawable.BitmapDrawable;
import android.widget.ImageButton;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import androidx.cardview.widget.CardView;
import androidx.core.content.FileProvider;

public class WritingPatternActivity extends AppCompatActivity {
    private FirebaseFirestore db;
    private TextView paragraphText, resultText;
    private ImageView scannedImage;
    private FrameLayout scanButton;
    private static final int REQUEST_IMAGE_CAPTURE = 1;

    // Add these new fields
    private float rotationAngle = 0f;
    private RectF cropRect;
    private boolean isCropping = false;
    private float lastTouchX, lastTouchY;
    private static final int CORNER_TOUCH_THRESHOLD = 50;
    private View cropOverlay;
    private LinearLayout editControls;
    private ImageButton rotateButton, cropButton;
    private Button confirmButton, cancelButton;
    private Bitmap originalBitmap;
    private Uri photoUri;



    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_writing_pattern);

        initViews();
        setupEditControls();
        initCropOverlay();
        db = FirebaseFirestore.getInstance();
        getRandomParagraph();

        scanButton.setOnClickListener(v -> startCamera());
    }

    private void initViews() {
        paragraphText = findViewById(R.id.paragraphText);
        resultText = findViewById(R.id.resultText);
        scannedImage = findViewById(R.id.scannedImage);
        scanButton = findViewById(R.id.scanContainer);
        editControls = findViewById(R.id.editControls);
        rotateButton = findViewById(R.id.rotateButton);
        cropButton = findViewById(R.id.cropButton);
        confirmButton = findViewById(R.id.confirmButton);
        cancelButton = findViewById(R.id.cancelButton);
        cropOverlay = findViewById(R.id.cropOverlay);
        ImageView cameraIcon = findViewById(R.id.cameraIcon);

        editControls.setVisibility(View.GONE);
        cropOverlay.setVisibility(View.GONE);
        scannedImage.setVisibility(View.GONE);
        cameraIcon.setVisibility(View.VISIBLE);
    }

    private void setupEditControls() {
        rotateButton.setOnClickListener(v -> rotateImage());
        cropButton.setOnClickListener(v -> startCropping());
        confirmButton.setOnClickListener(v -> confirmEdit());
        cancelButton.setOnClickListener(v -> cancelEdit());
    }

    private void initCropOverlay() {
        cropOverlay.setOnTouchListener((v, event) -> {
            if (!isCropping) return false;

            float x = event.getX();
            float y = event.getY();

            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    lastTouchX = x;
                    lastTouchY = y;
                    return true;

                case MotionEvent.ACTION_MOVE:
                    float dx = x - lastTouchX;
                    float dy = y - lastTouchY;
                    updateCropRect(dx, dy, x, y);
                    lastTouchX = x;
                    lastTouchY = y;
                    cropOverlay.invalidate();
                    return true;
            }
            return false;
        });
    }


    private void getRandomParagraph() {
        db.collection("practicepara")
                .document("writingprac")
                .get()
                .addOnSuccessListener(documentSnapshot -> {
                    if (documentSnapshot.exists()) {
                        Map<String, Object> data = documentSnapshot.getData();
                        Log.d("Firebase", "Data: " + data);

                        if (data != null && !data.isEmpty()) {
                            // Convert Object values to String
                            List<String> paragraphs = new ArrayList<>();
                            for (Object value : data.values()) {
                                paragraphs.add(value.toString());
                            }

                            Log.d("Firebase", "Paragraphs: " + paragraphs);

                            int randomIndex = new Random().nextInt(paragraphs.size());
                            String selectedParagraph = paragraphs.get(randomIndex);
                            Log.d("Firebase", "Selected: " + selectedParagraph);

                            paragraphText.setText(selectedParagraph);
                        } else {
                            Log.e("Firebase", "Data is null or empty");
                        }
                    } else {
                        Log.e("Firebase", "Document doesn't exist");
                    }
                })
                .addOnFailureListener(e -> {
                    Log.e("Firebase", "Error getting document", e);
                    Toast.makeText(WritingPatternActivity.this,
                            "Error loading paragraph: " + e.getMessage(),
                            Toast.LENGTH_SHORT).show();
                });
    }
    private void startCamera() {
        Intent takePictureIntent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);

        // Create file for full-size photo
        File photoFile = null;
        try {
            File storageDir = new File(getCacheDir(), "images");
            storageDir.mkdirs();
            photoFile = File.createTempFile(
                    "JPEG_" + System.currentTimeMillis() + "_",
                    ".jpg",
                    storageDir
            );
        } catch (IOException ex) {
            Toast.makeText(this, "Error creating image file", Toast.LENGTH_SHORT).show();
            return;
        }

        // Get URI using FileProvider
        photoUri = FileProvider.getUriForFile(
                this,
                getApplicationContext().getPackageName() + ".provider",
                photoFile
        );

        try {
            takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT, photoUri);
            startActivityForResult(takePictureIntent, REQUEST_IMAGE_CAPTURE);
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, "Camera not found", Toast.LENGTH_SHORT).show();
        }
    }


    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_IMAGE_CAPTURE && resultCode == RESULT_OK) {
            try {
                // Load full resolution image
                originalBitmap = MediaStore.Images.Media.getBitmap(getContentResolver(), photoUri);

                // Scale down if too large
                if (originalBitmap.getWidth() > 2048 || originalBitmap.getHeight() > 2048) {
                    float scale = Math.min(
                            2048f / originalBitmap.getWidth(),
                            2048f / originalBitmap.getHeight()
                    );
                    Matrix matrix = new Matrix();
                    matrix.postScale(scale, scale);
                    originalBitmap = Bitmap.createBitmap(
                            originalBitmap,
                            0, 0,
                            originalBitmap.getWidth(),
                            originalBitmap.getHeight(),
                            matrix,
                            true
                    );
                }

                // Show image and controls
                ImageView cameraIcon = findViewById(R.id.cameraIcon);
                scannedImage.setImageBitmap(originalBitmap);
                scannedImage.setVisibility(View.VISIBLE);
                cameraIcon.setVisibility(View.GONE);
                editControls.setVisibility(View.VISIBLE);
            } catch (IOException e) {
                Toast.makeText(this, "Error loading image", Toast.LENGTH_SHORT).show();
            }
        }
    }

    private void rotateImage() {
        rotationAngle = (rotationAngle + 90) % 360;

        // Create a new matrix for rotation
        Matrix matrix = new Matrix();
        matrix.postRotate(rotationAngle);

        // Create a new rotated bitmap
        Bitmap rotatedBitmap = Bitmap.createBitmap(
                originalBitmap,
                0,
                0,
                originalBitmap.getWidth(),
                originalBitmap.getHeight(),
                matrix,
                true
        );

        // Update the ImageView with the rotated bitmap
        scannedImage.setRotation(0);
        scannedImage.setImageBitmap(rotatedBitmap);

        // If cropping is active, update the crop bounds
        if (isCropping) {
            // Wait for the image layout to be updated
            scannedImage.post(() -> {
                // Get the new image bounds
                float[] matrixValues = new float[9];
                scannedImage.getImageMatrix().getValues(matrixValues);
                float scaleX = matrixValues[Matrix.MSCALE_X];
                float scaleY = matrixValues[Matrix.MSCALE_Y];
                float transX = matrixValues[Matrix.MTRANS_X];
                float transY = matrixValues[Matrix.MTRANS_Y];

                // Calculate new dimensions
                float drawableWidth = rotatedBitmap.getWidth() * scaleX;
                float drawableHeight = rotatedBitmap.getHeight() * scaleY;

                // Update crop rectangle to match new image bounds
                cropRect = new RectF(
                        transX,
                        transY,
                        transX + drawableWidth,
                        transY + drawableHeight
                );

                // Update the overlay
                ((CropOverlayView)cropOverlay).setCropRect(cropRect);
                cropOverlay.invalidate();
            });
        }
    }

    private void startCropping() {
        isCropping = true;
        cropOverlay.setVisibility(View.VISIBLE);

        // Get the current bitmap from ImageView
        Bitmap currentBitmap = ((BitmapDrawable) scannedImage.getDrawable()).getBitmap();

        // Get the image matrix
        float[] matrixValues = new float[9];
        scannedImage.getImageMatrix().getValues(matrixValues);
        float scaleX = matrixValues[Matrix.MSCALE_X];
        float scaleY = matrixValues[Matrix.MSCALE_Y];
        float transX = matrixValues[Matrix.MTRANS_X];
        float transY = matrixValues[Matrix.MTRANS_Y];

        // Calculate actual dimensions based on current bitmap
        float drawableWidth = currentBitmap.getWidth() * scaleX;
        float drawableHeight = currentBitmap.getHeight() * scaleY;

        // Calculate image bounds accounting for current state
        float imageLeft = transX;
        float imageTop = transY;
        float imageRight = imageLeft + drawableWidth;
        float imageBottom = imageTop + drawableHeight;

        // Initialize crop rectangle to match the actual current image bounds
        cropRect = new RectF(
                imageLeft,
                imageTop,
                imageRight,
                imageBottom
        );

        // Update the overlay
        ((CropOverlayView)cropOverlay).setCropRect(cropRect);
        cropOverlay.invalidate();
    }

    private void updateCropRect(float dx, float dy, float touchX, float touchY) {
        if (cropRect == null) return;

        // Get current bitmap from ImageView
        Bitmap currentBitmap = ((BitmapDrawable) scannedImage.getDrawable()).getBitmap();

        // Get current image matrix values
        float[] matrixValues = new float[9];
        scannedImage.getImageMatrix().getValues(matrixValues);
        float scaleX = matrixValues[Matrix.MSCALE_X];
        float scaleY = matrixValues[Matrix.MSCALE_Y];
        float transX = matrixValues[Matrix.MTRANS_X];
        float transY = matrixValues[Matrix.MTRANS_Y];

        // Calculate actual dimensions based on current bitmap
        float drawableWidth = currentBitmap.getWidth() * scaleX;
        float drawableHeight = currentBitmap.getHeight() * scaleY;

        // Calculate current image bounds
        float imageLeft = transX;
        float imageTop = transY;
        float imageRight = imageLeft + drawableWidth;
        float imageBottom = imageTop + drawableHeight;

        // Determine which corner/edge is being dragged
        boolean isNearLeft = Math.abs(touchX - cropRect.left) < CORNER_TOUCH_THRESHOLD;
        boolean isNearRight = Math.abs(touchX - cropRect.right) < CORNER_TOUCH_THRESHOLD;
        boolean isNearTop = Math.abs(touchY - cropRect.top) < CORNER_TOUCH_THRESHOLD;
        boolean isNearBottom = Math.abs(touchY - cropRect.bottom) < CORNER_TOUCH_THRESHOLD;

        // Update rectangle based on which corner/edge is being dragged
        float minSize = CORNER_TOUCH_THRESHOLD * 2; // Minimum crop size

        if (isNearLeft && touchX >= imageLeft) {
            cropRect.left = Math.min(cropRect.right - minSize, Math.max(imageLeft, touchX));
        }
        if (isNearRight && touchX <= imageRight) {
            cropRect.right = Math.max(cropRect.left + minSize, Math.min(imageRight, touchX));
        }
        if (isNearTop && touchY >= imageTop) {
            cropRect.top = Math.min(cropRect.bottom - minSize, Math.max(imageTop, touchY));
        }
        if (isNearBottom && touchY <= imageBottom) {
            cropRect.bottom = Math.max(cropRect.top + minSize, Math.min(imageBottom, touchY));
        }

        // Ensure crop rect stays within image bounds
        cropRect.left = Math.max(imageLeft, cropRect.left);
        cropRect.top = Math.max(imageTop, cropRect.top);
        cropRect.right = Math.min(imageRight, cropRect.right);
        cropRect.bottom = Math.min(imageBottom, cropRect.bottom);

        // Update the overlay
        ((CropOverlayView)cropOverlay).setCropRect(cropRect);
    }

    private void confirmEdit() {
        if (originalBitmap == null) return;

        // Get current bitmap from ImageView
        Bitmap editedBitmap = ((BitmapDrawable)scannedImage.getDrawable()).getBitmap();

        // Apply cropping if active
        if (isCropping && cropRect != null) {
            // Get current image matrix
            float[] matrixValues = new float[9];
            scannedImage.getImageMatrix().getValues(matrixValues);
            float scaleX = matrixValues[Matrix.MSCALE_X];
            float scaleY = matrixValues[Matrix.MSCALE_Y];
            float transX = matrixValues[Matrix.MTRANS_X];
            float transY = matrixValues[Matrix.MTRANS_Y];

            // Convert view coordinates to bitmap coordinates
            int left = Math.max(0, (int)((cropRect.left - transX) / scaleX));
            int top = Math.max(0, (int)((cropRect.top - transY) / scaleY));
            int width = (int)((cropRect.right - cropRect.left) / scaleX);
            int height = (int)((cropRect.bottom - cropRect.top) / scaleY);

            // Ensure dimensions are valid
            width = Math.min(width, editedBitmap.getWidth() - left);
            height = Math.min(height, editedBitmap.getHeight() - top);

            if (width > 0 && height > 0) {
                try {
                    editedBitmap = Bitmap.createBitmap(editedBitmap, left, top, width, height);
                } catch (IllegalArgumentException e) {
                    Toast.makeText(this, "Error cropping image", Toast.LENGTH_SHORT).show();
                    return;
                }
            }
        }

        // Update UI and process image
        scannedImage.setImageBitmap(editedBitmap);
        cropOverlay.setVisibility(View.GONE);
        editControls.setVisibility(View.GONE);
        recognizeText(editedBitmap);

        // Reset states
        rotationAngle = 0;
        cropRect = null;
        isCropping = false;
    }

    private void cancelEdit() {
        // Reset to original state
        scannedImage.setImageBitmap(originalBitmap);
        scannedImage.setRotation(0);
        cropOverlay.setVisibility(View.GONE);
        editControls.setVisibility(View.GONE);

        // Reset editing state
        rotationAngle = 0;
        cropRect = null;
        isCropping = false;
    }

    private void recognizeText(Bitmap bitmap) {
        InputImage image = InputImage.fromBitmap(bitmap, 0);
        TextRecognizer recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);

        recognizer.process(image)
                .addOnSuccessListener(text -> compareTexts(text.getText()))
                .addOnFailureListener(e -> Toast.makeText(this, "Text recognition failed", Toast.LENGTH_SHORT).show());
    }

    private void compareTexts(String scannedText) {
        String originalText = paragraphText.getText().toString();
        SpannableStringBuilder analysis = new SpannableStringBuilder();

        // Color-coded comparison
        String[] originalWords = originalText.split("\\s+");
        String[] scannedWords = scannedText.split("\\s+");
        addColorComparison(originalWords, scannedWords, analysis);
        analysis.append("\n\n");

        // Calculate accuracy
        int totalWords = originalWords.length;
        int correctWords = countCorrectWords(originalWords, scannedWords);
        float accuracy = (float) correctWords / totalWords * 100;

        // Maps for analysis
        Map<String, Integer> letterConfusions = new HashMap<>();
        Map<String, Integer> troubleLetters = new HashMap<>();
        Map<String, Integer> missingLetters = new HashMap<>();
        Map<String, Integer> extraLetters = new HashMap<>();
        Map<String, Integer> caseMistakes = new HashMap<>();
        Map<String, Integer> reversalPatterns = new HashMap<>();
        Map<String, Integer> soundPatterns = new HashMap<>();
        Map<String, Integer> sequenceErrors = new HashMap<>();
        Map<String, Integer> visualSimilarity = new HashMap<>();

        // Analyze patterns
        analyzeMistakes(originalWords, scannedWords, letterConfusions, troubleLetters,
                missingLetters, extraLetters, caseMistakes, reversalPatterns,
                soundPatterns, sequenceErrors, visualSimilarity);

        // Overall Analysis
        analysis.append(String.format("Accuracy: %.1f%%\n", accuracy));
        analysis.append(String.format("Correct words: %d/%d\n\n", correctWords, totalWords));

        // Basic Writing Analysis
        addStyledHeader(analysis, "Basic Writing Analysis", true);
        addSection(analysis, letterConfusions, "Letter Confusions:",
                e -> formatMistakeEntry(e, " times"));
        addSection(analysis, missingLetters, "Missing Letters:",
                e -> formatMistakeEntry(e, " times"));
        addSection(analysis, extraLetters, "Extra Letters:",
                e -> formatMistakeEntry(e, " times"));
        addSection(analysis, caseMistakes, "Case Mistakes:",
                e -> formatMistakeEntry(e, " times"));
        addSection(analysis, troubleLetters, "Trouble Letters:",
                e -> String.format("• Having trouble with '%s' (%d mistakes)", e.getKey(), e.getValue()));

        // Dyslexia Analysis
        addStyledHeader(analysis, "Dyslexia-Specific Analysis", true);
        addSection(analysis, reversalPatterns, "Letter Reversals:",
                e -> "• " + e.getKey());
        addSection(analysis, soundPatterns, "Sound Patterns:",
                e -> "• " + e.getKey());
        addSection(analysis, sequenceErrors, "Sequence Issues:",
                e -> "• " + e.getKey());
        addSection(analysis, visualSimilarity, "Visual Similarities:",
                e -> "• " + e.getKey());

        resultText.setText(analysis);
    }

    private void addColorComparison(String[] originalWords, String[] scannedWords,
                                    SpannableStringBuilder builder) {
        for (int i = 0; i < Math.min(originalWords.length, scannedWords.length); i++) {
            SpannableString wordSpan = new SpannableString(scannedWords[i]);
            int minLength = Math.min(originalWords[i].length(), scannedWords[i].length());

            for (int j = 0; j < scannedWords[i].length(); j++) {
                int color = (j < minLength && originalWords[i].charAt(j) == scannedWords[i].charAt(j))
                        ? Color.parseColor("#228B22") : Color.parseColor("#DC143C");
                wordSpan.setSpan(new ForegroundColorSpan(color), j, j + 1,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            builder.append(wordSpan).append(" ");
        }
    }

    private void addStyledHeader(SpannableStringBuilder builder, String text, boolean large) {
        SpannableString header = new SpannableString(text);
        header.setSpan(new StyleSpan(Typeface.BOLD), 0, text.length(),
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
        if (large) {
            header.setSpan(new RelativeSizeSpan(1.5f), 0, text.length(),
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            header.setSpan(new UnderlineSpan(), 0, text.length(), Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            builder.append(header).append("\n\n");
        } else {
            builder.append(header).append("\n");
        }
    }

    private void addSection(SpannableStringBuilder builder, Map<String, Integer> data,
                            String title, Function<Map.Entry<String, Integer>, String> formatter) {
        if (!data.isEmpty()) {
            addStyledHeader(builder, title, false);
            data.entrySet().stream()
                    .sorted((e1, e2) -> e2.getValue().compareTo(e1.getValue()))
                    .limit(3)
                    .forEach(e -> builder.append(formatter.apply(e)).append("\n"));
            builder.append("\n");
        }
    }

    private String formatMistakeEntry(Map.Entry<String, Integer> entry, String suffix) {
        return String.format("• %s (%d%s)", entry.getKey(), entry.getValue(), suffix);
    }

    private int countCorrectWords(String[] original, String[] scanned) {
        int count = 0;
        for (int i = 0; i < Math.min(original.length, scanned.length); i++) {
            if (original[i].equals(scanned[i])) count++;
        }
        return count;
    }

    private void analyzeMistakes(String[] originalWords, String[] scannedWords,
                                 Map<String, Integer> letterConfusions, Map<String, Integer> troubleLetters,
                                 Map<String, Integer> missingLetters, Map<String, Integer> extraLetters,
                                 Map<String, Integer> caseMistakes, Map<String, Integer> reversalPatterns,
                                 Map<String, Integer> soundPatterns, Map<String, Integer> sequenceErrors,
                                 Map<String, Integer> visualSimilarity) {

        for (int i = 0; i < Math.min(originalWords.length, scannedWords.length); i++) {
            String original = originalWords[i];
            String scanned = scannedWords[i];
            String originalLower = original.toLowerCase();
            String scannedLower = scanned.toLowerCase();

            checkBasicMistakes(original, scanned, originalLower, scannedLower,
                    letterConfusions, troubleLetters, missingLetters, extraLetters, caseMistakes);
            checkReversals(originalLower, scannedLower, reversalPatterns);
            checkPhoneticPatterns(originalLower, scannedLower, soundPatterns);
            checkSequenceErrors(originalLower, scannedLower, sequenceErrors);
            checkVisualSimilarities(originalLower, scannedLower, visualSimilarity);
        }
    }

    private void checkBasicMistakes(String original, String scanned,
                                    String originalLower, String scannedLower,
                                    Map<String, Integer> letterConfusions, Map<String, Integer> troubleLetters,
                                    Map<String, Integer> missingLetters, Map<String, Integer> extraLetters,
                                    Map<String, Integer> caseMistakes) {

        // Case mistakes
        for (int j = 0; j < Math.min(original.length(), scanned.length()); j++) {
            if (originalLower.charAt(j) == scannedLower.charAt(j) &&
                    original.charAt(j) != scanned.charAt(j)) {
                caseMistakes.put(String.valueOf(original.charAt(j)),
                        caseMistakes.getOrDefault(String.valueOf(original.charAt(j)), 0) + 1);
            }
        }

        // Missing letters
        for (char c : original.toCharArray()) {
            if (scanned.indexOf(c) == -1) {
                missingLetters.put(String.valueOf(c),
                        missingLetters.getOrDefault(String.valueOf(c), 0) + 1);
            }
        }

        // Extra letters
        for (char c : scanned.toCharArray()) {
            if (original.indexOf(c) == -1) {
                extraLetters.put(String.valueOf(c),
                        extraLetters.getOrDefault(String.valueOf(c), 0) + 1);
            }
        }

        // Letter confusions
        int len = Math.min(original.length(), scanned.length());
        for (int j = 0; j < len; j++) {
            if (originalLower.charAt(j) != scannedLower.charAt(j)) {
                String confusion = originalLower.charAt(j) + " with " + scannedLower.charAt(j);
                letterConfusions.put(confusion, letterConfusions.getOrDefault(confusion, 0) + 1);
                troubleLetters.put(String.valueOf(originalLower.charAt(j)),
                        troubleLetters.getOrDefault(String.valueOf(originalLower.charAt(j)), 0) + 1);
            }
        }
    }

    private void checkReversals(String original, String scanned, Map<String, Integer> patterns) {
        String[][] commonReversals = {
                {"b", "d"}, {"p", "q"}, {"n", "u"}, {"m", "w"},
                {"g", "q"}, {"f", "t"}, {"6", "9"}, {"2", "5"}
        };

        int len = Math.min(original.length(), scanned.length());
        for (int j = 0; j < len; j++) {
            char origChar = original.charAt(j);
            char scannedChar = scanned.charAt(j);
            if (origChar == scannedChar) continue;

            for (String[] pair : commonReversals) {
                if ((origChar == pair[0].charAt(0) && scannedChar == pair[1].charAt(0)) ||
                        (origChar == pair[1].charAt(0) && scannedChar == pair[0].charAt(0))) {
                    String key = "Reversing " + pair[0] + "/" + pair[1];
                    patterns.put(key, patterns.getOrDefault(key, 0) + 1);
                    break;
                }
            }
        }
    }

    private void checkPhoneticPatterns(String original, String scanned, Map<String, Integer> patterns) {
        Map<String, String[]> phoneticGroups = new HashMap<>();
        phoneticGroups.put("f", new String[]{"ph", "v"});
        phoneticGroups.put("s", new String[]{"c", "z"});
        phoneticGroups.put("k", new String[]{"c", "q"});
        phoneticGroups.put("j", new String[]{"g", "ch"});
        phoneticGroups.put("ee", new String[]{"ea", "ie"});
        phoneticGroups.put("ai", new String[]{"ay", "ei"});

        for (Map.Entry<String, String[]> group : phoneticGroups.entrySet()) {
            for (String sound : group.getValue()) {
                if ((original.contains(group.getKey()) && scanned.contains(sound)) ||
                        (original.contains(sound) && scanned.contains(group.getKey()))) {
                    String key = "Confusing " + group.getKey() + " sound with " + sound;
                    patterns.put(key, patterns.getOrDefault(key, 0) + 1);
                }
            }
        }
    }

    private void checkSequenceErrors(String original, String scanned, Map<String, Integer> patterns) {
        for (int i = 0; i < original.length() - 1 && i < scanned.length() - 1; i++) {
            if (i + 1 < original.length() && i + 1 < scanned.length()) {
                String origPair = original.substring(i, i + 2);
                String scannedPair = scanned.substring(i, i + 2);
                if (origPair.equals(new StringBuilder(scannedPair).reverse().toString())) {
                    String key = "Swapping " + origPair;
                    patterns.put(key, patterns.getOrDefault(key, 0) + 1);
                }
            }
        }
    }

    private void checkVisualSimilarities(String original, String scanned, Map<String, Integer> patterns) {
        Map<Character, char[]> visuallySimilar = new HashMap<>();
        visuallySimilar.put('h', new char[]{'n'});
        visuallySimilar.put('m', new char[]{'n'});
        visuallySimilar.put('i', new char[]{'l', '1'});
        visuallySimilar.put('o', new char[]{'0', 'a'});
        visuallySimilar.put('s', new char[]{'5'});
        visuallySimilar.put('z', new char[]{'2'});

        int len = Math.min(original.length(), scanned.length());
        for (int j = 0; j < len; j++) {
            char origChar = original.charAt(j);
            char scannedChar = scanned.charAt(j);
            if (origChar == scannedChar) continue;

            for (Map.Entry<Character, char[]> entry : visuallySimilar.entrySet()) {
                for (char similar : entry.getValue()) {
                    if ((origChar == entry.getKey() && scannedChar == similar) ||
                            (origChar == similar && scannedChar == entry.getKey())) {
                        String key = "Confusing visually similar " + entry.getKey() + " with " + similar;
                        patterns.put(key, patterns.getOrDefault(key, 0) + 1);
                    }
                }
            }
        }
    }
}