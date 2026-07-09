import argparse
import json
import time
import uuid
from datetime import datetime, timezone

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    PoseLandmarker,
    PoseLandmarkerOptions,
    RunningMode,
)

LANDMARK_NAMES = [
    "nose", "leftEyeInner", "leftEye", "leftEyeOuter",
    "rightEyeInner", "rightEye", "rightEyeOuter",
    "leftEar", "rightEar", "leftMouth", "rightMouth",
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
    "leftWrist", "rightWrist", "leftPinky", "rightPinky",
    "leftIndex", "rightIndex", "leftThumb", "rightThumb",
    "leftHip", "rightHip", "leftKnee", "rightKnee",
    "leftAnkle", "rightAnkle", "leftHeel", "rightHeel",
    "leftFootIndex", "rightFootIndex",
]

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_full/float16/latest/pose_landmarker_full.task"
)


def ensure_model(model_path: str):
    import os
    import urllib.request

    if os.path.exists(model_path):
        return
    print(f"Downloading pose landmarker model to {model_path} ...")
    urllib.request.urlretrieve(MODEL_URL, model_path)


def build_landmark_entry(index, name, lm_2d, lm_world, frame_w, frame_h):
    return {
        "index": index,
        "name": name,
        "x": lm_2d.x * frame_w,
        "y": lm_2d.y * frame_h,
        "xNorm": lm_2d.x,
        "yNorm": lm_2d.y,
        "z": lm_2d.z,
        "wx": lm_world.x if lm_world else 0.0,
        "wy": lm_world.y if lm_world else 0.0,
        "wz": lm_world.z if lm_world else 0.0,
        "visibility": lm_2d.visibility,
        "presence": lm_2d.presence if hasattr(lm_2d, "presence") else lm_2d.visibility,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video_path")
    parser.add_argument("output_json")
    parser.add_argument("--sample-fps", type=float, default=10.0)
    parser.add_argument("--model", default="pose_landmarker_full.task")
    parser.add_argument("--min-detection-confidence", type=float, default=0.5)
    args = parser.parse_args()

    ensure_model(args.model)

    cap = cv2.VideoCapture(args.video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Khong mo duoc video: {args.video_path}")

    frame_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    frame_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    record_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"Video: {frame_w}x{frame_h}, {record_fps:.2f}fps, {total_frames} frames")

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=args.model),
        running_mode=RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=args.min_detection_confidence,
        min_pose_presence_confidence=args.min_detection_confidence,
        min_tracking_confidence=args.min_detection_confidence,
    )

    frames_out = []
    sample_interval_ms = 1000.0 / args.sample_fps
    next_sample_ms = 0.0

    with PoseLandmarker.create_from_options(options) as landmarker:
        frame_idx = 0
        while True:
            ret, bgr = cap.read()
            if not ret:
                break

            timestamp_ms = int(frame_idx * 1000.0 / record_fps)
            frame_idx += 1

            if timestamp_ms < next_sample_ms:
                continue
            next_sample_ms += sample_interval_ms

            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            result = landmarker.detect_for_video(mp_image, timestamp_ms)

            if not result.pose_landmarks:
                frames_out.append({
                    "timestampMs": timestamp_ms,
                    "frameWidth": frame_w,
                    "frameHeight": frame_h,
                    "personDetected": False,
                    "avgVisibility": 0.0,
                    "distanceProxy": {"torsoLengthNorm": 0.0, "bboxHeightNorm": 0.0},
                    "landmarks": [],
                })
                continue

            lm_2d_list = result.pose_landmarks[0]
            lm_world_list = (
                result.pose_world_landmarks[0] if result.pose_world_landmarks else None
            )

            landmarks = [
                build_landmark_entry(
                    i, LANDMARK_NAMES[i], lm_2d_list[i],
                    lm_world_list[i] if lm_world_list else None,
                    frame_w, frame_h,
                )
                for i in range(33)
            ]

            avg_vis = sum(l["visibility"] for l in landmarks) / 33.0

            ls, rs = lm_2d_list[11], lm_2d_list[12]
            lh, rh = lm_2d_list[23], lm_2d_list[24]
            shoulder_c = ((ls.x + rs.x) / 2, (ls.y + rs.y) / 2)
            hip_c = ((lh.x + rh.x) / 2, (lh.y + rh.y) / 2)
            torso_len_norm = ((shoulder_c[0] - hip_c[0]) ** 2 + (shoulder_c[1] - hip_c[1]) ** 2) ** 0.5

            xs = [l["xNorm"] for l in landmarks]
            ys = [l["yNorm"] for l in landmarks]
            bbox_height_norm = max(ys) - min(ys)

            frames_out.append({
                "timestampMs": timestamp_ms,
                "frameWidth": frame_w,
                "frameHeight": frame_h,
                "personDetected": True,
                "avgVisibility": avg_vis,
                "distanceProxy": {
                    "torsoLengthNorm": torso_len_norm,
                    "bboxHeightNorm": bbox_height_norm,
                },
                "landmarks": landmarks,
            })

    cap.release()

    output = {
        "schemaVersion": "2.0",
        "capture": {
            "captureId": str(uuid.uuid4()),
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "exerciseId": None,
            "source": "mediapipe_pose_landmarker",
            "model": "full",
        },
        "device": {
            "platform": "python_reextract",
            "model": "n/a",
            "osVersion": "n/a",
            "appVersion": "reextract-0.1.0",
        },
        "captureParams": {
            "lensFacing": "unknown",
            "zoomFactor": 1.0,
            "previewResolution": "unknown",
            "frameResolution": f"{frame_w}x{frame_h}",
            "recordFps": record_fps,
            "sampleFps": args.sample_fps,
        },
        "frames": frames_out,
    }

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(output, f)

    print(f"Da ghi {len(frames_out)} frame vao {args.output_json}")


if __name__ == "__main__":
    main()
