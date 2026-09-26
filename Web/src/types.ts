export type OutputState = {
    uid: string;
    name: string;
    category: "system" | "blackhole";
    isBlackHole: boolean;
    available: boolean;
    outputChannels: number;
    volume: number | null;
    volumeWritable: boolean;
    muted: boolean | null;
    muteWritable: boolean;
    configured: boolean;
    levelReading: number | null;
    meterState?: string | null;
    routeError?: string | null;
};

export type DeviceState = {
    uid: string;
    name: string;
    category: "system" | "blackhole";
    available: boolean;
    outputChannels: number;
    inputChannels: number;
    savedAs: string[];
    muted: boolean;
    sourceLevel: number;
};

export type MixInputState = {
    kind: string;
    id: string;
    level: number;
    channelRouting: number[][];
    channelLevels: number[];
    channelsLinked: boolean;
    muted: boolean;
    sourceMuted: boolean;
    levelReading: number | null;
};

export type MixState = {
    target: "output" | "bus" | "route";
    id: string;
    level: number;
    inputs: MixInputState[];
    levelReading: number | null;
};

export type MixerState = {
    schemaVersion: number;
    isEnabled: boolean;
    devices: DeviceState[];
    outputs: OutputState[];
    buses: {
        id: string;
        name: string;
        category: "virtual";
        muted: boolean;
        sourceLevel: number;
    }[];
    blackHoleRoutes: {
        id: string;
        name: string;
        category: "blackhole";
        deviceUID: string;
        channels: number[];
        available: boolean;
        captureState: string;
        level: number | null;
        muted: boolean;
        sourceLevel: number;
    }[];
    applications: {
        id: string;
        name: string;
        available: boolean;
        registered: boolean;
        muted: boolean;
        captureState: string;
        level: number | null;
        sourceLevel: number;
    }[];
    inputCaptureStates: {
        uid: string;
        state: string;
        level: number | null;
        channelLevels: (number | null)[];
    }[];
    mixes: MixState[];
};

export type BridgeCommand =
    | { command: "ready" }
    | { command: "openPrivacySettings" }
    | { command: "setMasterEnabled"; enabled: boolean }
    | { command: "setDeviceVolume"; uid: string; level: number }
    | { command: "setDeviceMuted"; uid: string; muted: boolean }
    | { command: "setBusMuted"; id: string; muted: boolean }
    | {
          command: "setVirtualMixLevel";
          target: "bus" | "route";
          id: string;
          level: number;
      }
    | { command: "deleteOutputMix"; uid: string }
    | { command: "resetMix"; target: "output" | "bus" | "route"; id: string }
    | {
          command: "setSourceMuted";
          kind:
              "inputDevice" | "application" | "app" | "bus" | "blackHoleRoute";
          sourceID: string;
          muted: boolean;
      }
    | {
          command: "setSourceLevel";
          kind:
              "inputDevice" | "application" | "app" | "blackHoleRoute" | "bus";
          sourceID: string;
          level: number;
      }
    | { command: "createBus" }
    | { command: "renameBus"; id: string; name: string }
    | { command: "renameRoute"; id: string; name: string }
    | {
          command: "createRoute";
          deviceUID: string;
      }
    | { command: "deleteRoute"; id: string }
    | { command: "deleteBus"; id: string }
    | { command: "addApplicationInput"; applicationID: string }
    | {
          command: "addMixInput" | "removeMixInput";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
      }
    | {
          command: "setMixInputLevel";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
          level: number;
      }
    | {
          command: "setMixInputMuted";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
          muted: boolean;
      }
    | {
          command: "setMixInputRouting";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
          channelRouting: number[][];
      }
    | {
          command: "setPhysicalInputChannels";
          target: "output" | "bus" | "route";
          id: string;
          kind: "inputDevice";
          sourceID: string;
          channelLevels: number[];
          channelsLinked: boolean;
      };

declare global {
    interface Window {
        soundMixerBridge?: {
            onState: (state: MixerState) => void;
            onNotification: (notification: { message: string }) => void;
            onCommandResult: (result: {
                requestId: string;
                accepted: boolean;
                error?: string;
            }) => void;
            send: (command: BridgeCommand) => Promise<void>;
        };
        webkit?: {
            messageHandlers: {
                soundMixer: { postMessage: (message: unknown) => void };
            };
        };
    }
}
