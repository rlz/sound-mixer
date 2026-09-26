export const MIN_GAIN_DECIBELS = -60;

export const gainToDecibels = (gain: number) =>
    gain <= 0
        ? MIN_GAIN_DECIBELS
        : Math.max(MIN_GAIN_DECIBELS, 20 * Math.log10(gain));

export const decibelsToGain = (decibels: number) =>
    decibels <= MIN_GAIN_DECIBELS ? 0 : Math.pow(10, decibels / 20);

export const formatGainDecibels = (decibels: number) =>
    decibels <= MIN_GAIN_DECIBELS
        ? "Mute"
        : `${decibels > 0 ? "+" : ""}${decibels.toFixed(1)} dB`;
