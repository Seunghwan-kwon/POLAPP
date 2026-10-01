# POLAPP YAMNet ONNX

Source: TensorFlow Hub google/yamnet/1
Training ontology: AudioSet 521 classes
Input: mono 16 kHz float32 waveform
Output: frame-level class scores

POLAPP uses selected scores as supporting evidence only. AudioSet is not a Korean police-field validation set; false alarms per hour and event F1 must be measured with a separate consented field set before operational use.
