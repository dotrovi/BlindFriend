import 'package:flutter/material.dart';

/// Shared "night sky" dark theme palette used across BlindFriend's
/// voice-first pages (login, home, etc.) so the look stays consistent.
const Color kNavyDeep = Color(0xFF120A2E);
const Color kNavyMid = Color(0xFF1E1147);
const Color kPurple = Color(0xFF3B1E78);
const Color kPinkBright = Color(0xFFFF5FD2);
const Color kBlueAccent = Color(0xFF4A90E2);
const Color kCardFill = Color(0xFF241A45);

const Color kAmberAccent = Color(0xFFFFA726);
const Color kTealAccent = Color(0xFF26C6DA);
const Color kPurpleAccent = Color(0xFF9B6BFF);
const Color kRedAccent = Color(0xFFFF5C5C);

const LinearGradient kSkyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kNavyDeep, kNavyMid, kPurple],
);

const LinearGradient kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kPinkBright, Color(0xFF9B59B6), kBlueAccent],
);
