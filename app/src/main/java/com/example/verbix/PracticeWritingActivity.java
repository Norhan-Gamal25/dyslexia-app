package com.example.verbix;

import android.os.Bundle;

import android.graphics.Color;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import com.google.mlkit.vision.digitalink.DigitalInkRecognizer;
import com.google.mlkit.vision.digitalink.DigitalInkRecognition;
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModel;
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModelIdentifier;

import com.google.firebase.firestore.FirebaseFirestore;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.common.model.RemoteModelManager;

import com.google.mlkit.vision.digitalink.DigitalInkRecognizerOptions;
import com.google.mlkit.vision.digitalink.Ink;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;

public class PracticeWritingActivity extends AppCompatActivity {
    private DrawingView drawingView;
    private TextView wordToWrite;
    private TextView resultText;
    private DigitalInkRecognizer recognizer;
    private String currentWord;
    private FirebaseFirestore db;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_practice_writing);

        // Initialize views
        drawingView = findViewById(R.id.drawing_view);
        wordToWrite = findViewById(R.id.wordToWrite);
        resultText = findViewById(R.id.resultText);
        Button checkButton = findViewById(R.id.checkButton);
        Button nextWordButton = findViewById(R.id.nextWordButton);
        Button clearButton = findViewById(R.id.clearButton);

        // Initialize Firestore
        db = FirebaseFirestore.getInstance();

        // Initialize recognizer
        try {
            DigitalInkRecognitionModelIdentifier modelIdentifier =
                    DigitalInkRecognitionModelIdentifier.fromLanguageTag("en-US");
            if (modelIdentifier == null) {
                Log.e("Recognition", "Model not available");
                return;
            }

            DigitalInkRecognitionModel model =
                    DigitalInkRecognitionModel.builder(modelIdentifier).build();

            // Download the model if it's not already downloaded
            RemoteModelManager.getInstance().download(model, new DownloadConditions.Builder().build())
                    .addOnSuccessListener(aVoid -> {
                        // Model downloaded successfully. Create recognizer
                        DigitalInkRecognizerOptions options =
                                DigitalInkRecognizerOptions.builder(model).build();
                        recognizer = DigitalInkRecognition.getClient(options);
                    })
                    .addOnFailureListener(e -> {
                        Log.e("Recognition", "Error downloading model", e);
                    });

        } catch (Exception e) {
            Log.e("Recognition", "Error initializing recognizer", e);
        }

        // Set up button listeners
        checkButton.setOnClickListener(v -> checkWriting());
        nextWordButton.setOnClickListener(v -> loadNextWord());
        clearButton.setOnClickListener(v -> drawingView.clear());

        // Load initial word
        loadNextWord();
    }

    private void loadNextWord() {
        db.collection("practicepara")
                .document("words")
                .get()
                .addOnSuccessListener(documentSnapshot -> {
                    if (documentSnapshot.exists()) {
                        Map<String, Object> fields = documentSnapshot.getData();
                        if (fields != null && !fields.isEmpty()) {
                            List<String> words = new ArrayList<>();
                            for (Object value : fields.values()) {
                                words.add(value.toString());
                            }
                            currentWord = words.get(new Random().nextInt(words.size()));
                            wordToWrite.setText(currentWord);
                            resultText.setText("");
                            drawingView.clear();
                        } else {
                            Log.e("Firestore", "No words found in the document");
                        }
                    } else {
                        Log.e("Firestore", "Document doesn't exist");
                    }
                })
                .addOnFailureListener(e -> {
                    Log.e("Firestore", "Error getting document", e);
                });
    }

    private void checkWriting() {
        Ink ink = drawingView.getInk();
        if (ink.getStrokes().isEmpty()) {
            resultText.setText("Please write something first");
            return;
        }

        if (recognizer == null) {
            resultText.setText("Handwriting model is still loading. Please wait a moment and try again.");
            return;
        }

        recognizer.recognize(ink)
                .addOnSuccessListener(result -> {
                    if (!result.getCandidates().isEmpty()) {
                        String recognizedText = result.getCandidates().get(0).getText();
                        compareAndHighlight(recognizedText, currentWord);
                    } else {
                        resultText.setText("Could not recognize the writing. Please try again.");
                    }
                })
                .addOnFailureListener(e -> {
                    resultText.setText("Recognition failed. Please try again.");
                });
    }


    private void compareAndHighlight(String recognized, String target) {
        if (resultText == null) return;

        String displayText = "Written: " + recognized + "\nTarget: " + target;
        SpannableString spannableString = new SpannableString(displayText);

        int recognizedStart = 9;
        for (int i = 0; i < recognized.length(); i++) {
            int position = recognizedStart + i;
            if (i < target.length() && recognized.charAt(i) == target.charAt(i)) {
                spannableString.setSpan(
                        new ForegroundColorSpan(Color.parseColor("#228B22")),
                        position, position + 1,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                );
            } else {
                spannableString.setSpan(
                        new ForegroundColorSpan(Color.parseColor("#B22222")),
                        position, position + 1,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                );
            }
        }

        resultText.setText(spannableString);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (recognizer != null) {
            recognizer.close();
        }
    }
}