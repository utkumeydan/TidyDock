import React from "react";
import { Composition } from "remotion";
import { DURATION, Video } from "./Video";

export const Root: React.FC = () => (
  <>
    <Composition id="TidyDock-tr" component={Video} durationInFrames={DURATION} fps={30} width={1080} height={1080} defaultProps={{ lang: "tr" as const }} />
    <Composition id="TidyDock-en" component={Video} durationInFrames={DURATION} fps={30} width={1080} height={1080} defaultProps={{ lang: "en" as const }} />
  </>
);
