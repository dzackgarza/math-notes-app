// google/ink core on the engine targets: outlines against Linux host goldens,
// incremental strokes, hit tests, and an eraser split.
#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <string>
#include <vector>

#include "geometry/hit_shapes.h"
#include "ink/brush/stock_brushes.h"
#include "ink/geometry/affine_transform.h"
#include "ink/geometry/intersects.h"
#include "ink/geometry/rect.h"
#include "ink/geometry/segment.h"
#include "ink/strokes/in_progress_stroke.h"
#include "ink/strokes/stroke.h"
#include "ink/types/duration.h"
#include "support/trace.h"

namespace {

const std::string kFixtures = INK_FIXTURE_DIR "/ink/";

// iOS disables FMA contraction in vec.h (google/ink 9d53674), so outlines agree
// across targets only to a tolerance.
constexpr float kTolerance = 1e-3f;

// google/ink models inputs incrementally in a sliding window, so a stroke
// built frame by frame can differ from one built at once. With PressurePen on
// the recorded traces the gap is 0.115 units (brush size 5), with or without
// predicted inputs; with Marker and Highlighter it is 0.
constexpr float kIncrementalTolerance = 0.2f;

void RequireSameOutline(const std::vector<ink_test::OutlineVertex> &actual,
                        const std::vector<ink_test::OutlineVertex> &expected,
                        float tolerance = kTolerance) {
  REQUIRE(actual.size() == expected.size());
  for (size_t i = 0; i < actual.size(); ++i) {
    INFO("vertex " << i);
    REQUIRE(actual[i].group == expected[i].group);
    REQUIRE(actual[i].outline == expected[i].outline);
    REQUIRE(std::abs(actual[i].position.x - expected[i].position.x) <= tolerance);
    REQUIRE(std::abs(actual[i].position.y - expected[i].position.y) <= tolerance);
  }
}

ink::Stroke BuildIncrementally(const ink::Brush &brush,
                               const std::vector<ink_test::TraceFrame> &frames) {
  ink::InProgressStroke stroke;
  stroke.Start(brush);
  for (size_t i = 0; i < frames.size(); ++i) {
    // The pen-up frame carries no prediction. The sliding-window modeler
    // smooths the last real inputs over predicted ones, and neither
    // FinishInputs() nor an empty EnqueueInputs() re-models them.
    bool pen_up = i + 1 == frames.size();
    REQUIRE(stroke.EnqueueInputs(frames[i].real, pen_up ? ink::StrokeInputBatch() : frames[i].predicted).ok());
    // Update to the time of the newest real input.
    if (!frames[i].real.IsEmpty()) {
      REQUIRE(stroke.UpdateShape(frames[i].real.Get(frames[i].real.Size() - 1).elapsed_time).ok());
    }
  }
  stroke.FinishInputs();
  REQUIRE(stroke.UpdateShape(ink::Duration32::Infinite()).ok());
  return stroke.CopyToStroke();
}

ink::StrokeInputBatch HorizontalLine(float y, float x0, float x1, int count) {
  ink::StrokeInputBatch batch;
  for (int i = 0; i < count; ++i) {
    float t = float(i) / float(count - 1);
    REQUIRE(batch
                .Append({.tool_type = ink::StrokeInput::ToolType::kStylus,
                         .position = {x0 + t * (x1 - x0), y},
                         .elapsed_time = ink::Duration32::Seconds(t)})
                .ok());
  }
  return batch;
}

ink::Brush Marker() {
  return *ink::Brush::Create(ink::stock_brushes::Marker(ink::stock_brushes::MarkerVersion::kV1),
                             ink::Color::Black(), 5, 0.1);
}

}  // namespace

TEST_CASE("Stock brush outlines match the Linux host goldens") {
  for (const std::string &trace : ink_test::kTraceNames) {
    ink::StrokeInputBatch inputs = ink_test::RealInputs(ink_test::ReadTrace(kFixtures + trace + ".trace"));
    for (const auto &[name, brush] : ink_test::StockTestBrushes()) {
      INFO(trace << " / " << name);
      RequireSameOutline(ink_test::Outline(ink::Stroke(brush, inputs)),
                         ink_test::ReadOutline(kFixtures + trace + "." + name + ".outline"));
    }
  }
}

TEST_CASE("InProgressStroke with predicted inputs finishes as the complete stroke") {
  for (const std::string &trace : ink_test::kTraceNames) {
    auto frames = ink_test::ReadTrace(kFixtures + trace + ".trace");
    for (const auto &[name, brush] : ink_test::StockTestBrushes()) {
      INFO(trace << " / " << name);
      RequireSameOutline(ink_test::Outline(BuildIncrementally(brush, frames)),
                         ink_test::Outline(ink::Stroke(brush, ink_test::RealInputs(frames))),
                         kIncrementalTolerance);
    }
  }
}

TEST_CASE("Eraser quad and lasso hit-test a stroke") {
  ink::Stroke line(Marker(), HorizontalLine(100, 0, 200, 50));
  const ink::PartitionedMesh &shape = line.GetShape();

  auto eraser = [](ink::Point a, ink::Point b) {
    return ink_engine::EraserQuad(ink::Segment{a, b}, 2);
  };
  CHECK(ink::Intersects(eraser({100, 80}, {100, 120}), shape, ink::AffineTransform()));
  CHECK_FALSE(ink::Intersects(eraser({100, 150}, {100, 190}), shape, ink::AffineTransform()));

  // A lasso around the left half covers about half of the stroke.
  auto half = ink_engine::LassoMesh(std::vector<ink::Point>{{-10, 80}, {100, 80}, {100, 120}, {-10, 120}});
  REQUIRE(half.ok());
  CHECK(shape.CoverageIsGreaterThan(*half, 0.4f));
  CHECK_FALSE(shape.CoverageIsGreaterThan(*half, 0.6f));

  auto around = ink_engine::LassoMesh(std::vector<ink::Point>{{-20, 60}, {220, 60}, {220, 140}, {-20, 140}});
  REQUIRE(around.ok());
  CHECK(shape.CoverageIsGreaterThan(*around, 0.99f));

  auto away = ink_engine::LassoMesh(std::vector<ink::Point>{{0, 300}, {50, 300}, {50, 350}});
  REQUIRE(away.ok());
  CHECK_FALSE(shape.CoverageIsGreaterThan(*away, 0.0f));
}

TEST_CASE("An eraser segment splits a stroke's inputs into two strokes") {
  ink::StrokeInputBatch inputs = HorizontalLine(100, 0, 200, 101);
  ink::Quad eraser = ink_engine::EraserQuad(ink::Segment{{100, 50}, {100, 150}}, 10);

  // Inputs inside the eraser are removed; the runs on either side remain.
  std::vector<ink::StrokeInputBatch> pieces(1);
  for (size_t i = 0; i < inputs.Size(); ++i) {
    ink::StrokeInput input = inputs.Get(i);
    if (ink::Intersects(eraser, input.position)) {
      if (!pieces.back().IsEmpty()) pieces.emplace_back();
      continue;
    }
    REQUIRE(pieces.back().Append(input).ok());
  }
  if (pieces.back().IsEmpty()) pieces.pop_back();
  REQUIRE(pieces.size() == 2);

  ink::Rect left = *ink::Stroke(Marker(), pieces[0]).GetShape().Bounds().AsRect();
  ink::Rect right = *ink::Stroke(Marker(), pieces[1]).GetShape().Bounds().AsRect();
  // Brush size 5: the outline extends 2.5 past the last input on each side.
  CHECK(std::abs(left.XMin() - -2.5f) < 0.1f);
  CHECK(std::abs(left.XMax() - (88 + 2.5f)) < 0.1f);
  CHECK(std::abs(right.XMin() - (112 - 2.5f)) < 0.1f);
  CHECK(std::abs(right.XMax() - (200 + 2.5f)) < 0.1f);
}

// A measurement, not a test: run with `ink_tests "[.benchmark]"`.
TEST_CASE("EnqueueInputs plus UpdateShape per 16-input frame", "[.benchmark]") {
  auto frames = ink_test::ReadTrace(kFixtures + "spring_shape.trace");
  ink::Brush pen = ink_test::StockTestBrushes()[1].brush;
  ink::StrokeInputBatch all = ink_test::RealInputs(frames);
  std::vector<ink::StrokeInputBatch> batches;
  for (size_t i = 0; i + 16 <= all.Size(); i += 16) {
    ink::StrokeInputBatch frame;
    for (size_t j = i; j < i + 16; ++j) REQUIRE(frame.Append(all.Get(j)).ok());
    batches.push_back(std::move(frame));
  }
  REQUIRE_FALSE(batches.empty());
  BENCHMARK("whole recorded stroke, frame by frame") {
    ink::InProgressStroke stroke;
    stroke.Start(pen);
    for (const ink::StrokeInputBatch &frame : batches) {
      REQUIRE(stroke.EnqueueInputs(frame, {}).ok());
      REQUIRE(stroke.UpdateShape(frame.Get(frame.Size() - 1).elapsed_time).ok());
    }
    return stroke.BrushCoatCount();
  };
}
