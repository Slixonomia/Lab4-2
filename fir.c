#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
    for (int i = 0; i < N; i++) {
        outputsignal[i] = 0;
    }
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir() {
    initfir();
    
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            int k = i - j;
            if (k >= 0 && k < N) {
                outputsignal[i] += taps[j] * inputsignal[k];
            }

        }
    }
    
    return outputsignal;
}