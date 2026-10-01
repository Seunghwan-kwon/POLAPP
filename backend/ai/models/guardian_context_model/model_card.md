# POLAPP Guardian Context Model

Base: klue/roberta-small
Dataset: KCDD official split
Seeds: [13, 42, 77]
Test Macro-F1 mean/std: 0.8724 / 0.0034
Test Accuracy mean/std: 0.8724 / 0.0033

Limitations: KCDD is an online-dialogue corpus, so field audio
transcripts require separate external validation. Output is decision
support, not an automatic police action.
