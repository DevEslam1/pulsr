package com.pulsr.music

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Verifies that the golden contract fixture for battery telemetry
 * (test/fixtures/contracts/dsp_battery_estimate.json) matches the keys and
 * structure produced by AudioEffectsPlugin.getDspBatteryDrainEstimate().
 */
class DspBatteryEstimateContractTest {

    @Test
    fun fixtureMatchesContractSpecification() {
        val jsonText = fixtureSource()
        val json = JSONObject(jsonText)

        val requiredKeys = listOf(
            "isHeuristic",
            "dspActive",
            "lowPowerBypassActive",
            "activeStageCount",
            "activeStagesCount",
            "rollingRtf",
            "baselineMahPerHour",
            "estimatedMahPerHour",
            "dspDeltaMahPerHour",
            "stageBreakdown",
            "stageBreakdownList",
            "stagePowerSpecs",
            "thermalStatus",
            "thermalStatusName",
            "proactivelyDegradedStages"
        )

        for (key in requiredKeys) {
            assertTrue("Golden fixture missing required key '$key'", json.has(key))
        }

        // Verify type invariants
        assertTrue(json.get("stageBreakdown") is JSONObject)
        assertTrue(json.get("stageBreakdownList") is org.json.JSONArray)
        assertTrue(json.get("stagePowerSpecs") is JSONObject)
        assertEquals(3, json.getInt("activeStageCount"))
        assertEquals(3, json.getInt("activeStagesCount"))

        val breakdownList = json.getJSONArray("stageBreakdownList")
        assertEquals(3, breakdownList.length())
        for (i in 0 until breakdownList.length()) {
            val item = breakdownList.getJSONObject(i)
            assertTrue(item.has("stageId"))
            assertTrue(item.has("name"))
            assertTrue(item.has("mahPerHour"))
            assertTrue(item.has("sharePercent"))
            assertTrue(item.has("isHeavy"))
        }
    }

    private fun fixtureSource(): String {
        val candidates = listOf(
            "../../test/fixtures/contracts/dsp_battery_estimate.json",
            "../test/fixtures/contracts/dsp_battery_estimate.json",
            "test/fixtures/contracts/dsp_battery_estimate.json"
        )
        for (candidate in candidates) {
            val file = File(candidate)
            if (file.isFile) return file.readText()
        }
        fail("dsp_battery_estimate.json fixture not found from ${File(".").absolutePath}")
        error("unreachable")
    }
}
