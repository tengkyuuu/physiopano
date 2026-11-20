const { initializeApp } = require("firebase-admin/app");

initializeApp();
exports.getReferralOutcomes = require("./getReferralOutcomes").getReferralOutcomes;
