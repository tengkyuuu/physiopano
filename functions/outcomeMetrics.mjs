const HOUR = 3.6e6;
const stationHours = { primaryCare: 72, teleMH: 48 };
const dimensions = ["ageBand", "gender", "nationalityGroup", "language", "area"];

function uniquePeople(rows) {
  return new Set(rows.map(row => row.uid)).size;
}

function median(values) {
  const ordered = values.slice().sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2 === 1 ? ordered[middle] :
    (ordered[middle - 1] + ordered[middle]) / 2;
}

function measured(rows, minimum, summarize) {
  if (rows.length === 0 || uniquePeople(rows) < minimum) return null;
  return { value: summarize(rows), count: rows.length };
}

function percent(rows, predicate) {
  return 100 * rows.filter(predicate).length / rows.length;
}

function elapsed(row, at) {
  return at !== undefined && at >= row.createdAt ? (at - row.createdAt) / HOUR : null;
}

export function reportOutcomes(rows, now, privacyMinimum = 5) {
  function summarize(sample, minimum) {
    const routine = sample.filter(row => row.kind === "referral");
    const urgent = sample.filter(row => row.kind === "urgent" &&
      now - row.createdAt >= HOUR / 4);
    const due = routine.filter(row => row.outcomeConsent && stationHours[row.station] &&
      now >= row.createdAt + (stationHours[row.station] + 24) * HOUR);
    const paired = (instrument, field) => sample.filter(row =>
      row.outcomeConsent && row.initial?.instrument === instrument &&
      Number.isFinite(row.initial.total) && Number.isFinite(row.followUp?.[field]));
    const change = field => members => median(members.map(row =>
      row.followUp[field] - row.initial.total));
    return {
      handoff: measured(routine, minimum, members =>
        percent(members, row => elapsed(row, row.acceptedAt) !== null)),
      timelyFollowUp: measured(due, Math.max(minimum, privacyMinimum), members =>
        percent(members, row => {
          const hours = elapsed(row, row.followUp?.submittedAt);
          return hours !== null && hours >= stationHours[row.station] &&
            hours <= stationHours[row.station] + 24;
        })),
      urgentContact: measured(urgent, minimum, members =>
        percent(members, row => {
          const hours = elapsed(row, row.firstContactAt);
          return hours !== null && hours <= 0.25;
        })),
      adverseEvents: measured(sample, minimum, members =>
        members.reduce((count, row) => count + (row.adverseEventCount ?? 0), 0)),
      phq4Change: measured(paired("PHQ-4", "phq4Total"),
        Math.max(minimum, privacyMinimum), change("phq4Total")),
      pss4Change: measured(paired("PSS-4", "pss4Total"),
        Math.max(minimum, privacyMinimum), change("pss4Total")),
    };
  }

  function stations(sample, minimum) {
    return Object.fromEntries(["community", "primaryCare", "teleMH", "specialist"].map(station => {
      const contacted = sample.filter(row => row.station === station &&
        row.kind === "referral" && elapsed(row, row.firstContactAt) !== null);
      return [station, measured(contacted, minimum, members =>
        median(members.map(row => elapsed(row, row.firstContactAt))))];
    }));
  }

  const groups = Object.fromEntries(dimensions.map(dimension => {
    const grouped = new Map();
    for (const row of rows) {
      const label = row.outcomeConsent && row.demographics?.[dimension];
      if (!label) continue;
      const group = grouped.get(label) ?? [];
      group.push(row);
      grouped.set(label, group);
    }
    return [dimension, [...grouped]
      .filter(([, sample]) => uniquePeople(sample) >= privacyMinimum)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([label, sample]) => ({
        label,
        metrics: summarize(sample, privacyMinimum),
        stations: stations(sample, privacyMinimum),
      }))];
  }));
  return { sampleSize: rows.length, metrics: summarize(rows, 1),
    stations: stations(rows, 1), groups };
}
