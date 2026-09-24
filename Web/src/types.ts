export type OutputState = {
    uid: string;
    name: string;
    isBlackHole: boolean;
    available: boolean;
    outputChannels: number;
    level: number;
    configured: boolean;
    levelReading: number | null;
    routeError?: string | null;
};

export type DeviceState = {
    uid: string;
    name: string;
    available: boolean;
    outputChannels: number;
    inputChannels: number;
    savedAs: string[];
    muted: boolean;
};

export type MixInputState = {
    kind: string;
    id: string;
    level: number;
    monoPlacement: "left" | "right" | "both";
    channelRouting: ("ignore" | "first" | "second" | "both")[];
    channelLevels: number[];
    channelsLinked: boolean;
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
    buses: { id: string; name: string }[];
    blackHoleRoutes: {
        id: string;
        name: string;
        deviceUID: string;
        channels: number[];
    }[];
    applications: {
        id: string;
        name: string;
        available: boolean;
        muted: boolean;
        captureState: string;
        level: number | null;
    }[];
    inputCaptureStates: { uid: string; state: string; level: number | null }[];
    mixes: MixState[];
};

export type BridgeCommand =
    | { command: "ready" }
    | { command: "openPrivacySettings" }
    | { command: "setMasterEnabled"; enabled: boolean }
    | { command: "setOutputLevel"; uid: string; level: number }
    | { command: "deleteOutputMix"; uid: string }
    | {
          command: "setSourceMuted";
          kind: "inputDevice" | "application";
          sourceID: string;
          muted: boolean;
      }
    | { command: "createBus"; name: string }
    | { command: "renameBus"; id: string; name: string }
    | { command: "renameRoute"; id: string; name: string }
    | {
          command: "createRoute";
          name: string;
          deviceUID: string;
          mode: "mono" | "stereo";
          channels: number[];
      }
    | { command: "deleteRoute"; id: string }
    | { command: "deleteBus"; id: string }
    | {
          command: "addMixInput" | "removeMixInput";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
          monoPlacement?: "left" | "right" | "both";
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
          command: "setMonoPlacement";
          target: "output" | "bus" | "route";
          id: string;
          kind: string;
          sourceID: string;
          monoPlacement: "left" | "right" | "both";
      }
    | {
          command: "setPhysicalInputChannels";
          target: "output" | "bus" | "route";
          id: string;
          sourceID: string;
          channelRouting: ("ignore" | "first" | "second" | "both")[];
          channelLevels: number[];
          channelsLinked: boolean;
      };

declare global {
    interface Window {
        soundMixerBridge?: {
            onState: (state: MixerState) => void;
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
